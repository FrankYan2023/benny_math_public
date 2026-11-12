import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/ai_service.dart';
import '../ai/ai_tasks.dart' show maxKnown;
import '../game/game_data.dart';
import '../game/monster.dart';
import '../game/player.dart';
import '../game/treasure.dart';
import '../i18n.dart';
import '../models/hunt.dart';
import '../models/jail.dart';
import '../models/knowledge.dart';
import '../services/local_db.dart';
import '../services/settings.dart';
import 'answer_check.dart';
import 'coach_controller.dart';
import 'photo_hash.dart';

class BusyState {
  BusyState(this.label) : startedAt = DateTime.now();
  final String label;
  final DateTime startedAt;
}

class HuntError {
  HuntError(this.message, this.code, this.retry);
  final String message;
  final String code;
  final Future<void> Function()? retry;
}

/// 一次打怪的流程控制。每道错题只调用两次 GPT：
///   1. analyze：看照片，诊断错因和要补的知识点
///   2. training：一次生成全部知识点的讲解、例题和练习
/// 结果整份存进本机数据库（LocalDb），以后打开直接读。
/// 村庄修炼（从冒险地图点开一个知识点）只有第 2 步，存进这个知识点的村庄存档。练习和重做原题都是输入答案，由 App 比对；
/// 知识点状态按确定的规则计算（lib/logic/mastery.dart）。
/// 放弃（或者答错两次）的原题和小怪不直接给答案：关进怪兽监狱，一步一步来（steps 拆一次，每拍一步 stepcheck 一次），见 CoachController。
class HuntController extends ChangeNotifier {
  HuntController({required this.session, required this.settings, required this.kb, this.ai, LocalDb? db})
      : _db = db ?? LocalDb.instance;

  final HuntSession session;
  final AppSettings settings;
  final Knowledge kb;
  final AiService? ai; // 没登录 ChatGPT 时为空：只能打开已经生成好修炼内容的题
  final LocalDb _db;

  /// AI 来源（显示给用户看）
  String get aiLabel => ai?.label ?? tr('未連線', 'not connected', 'sin conexión');

  // 照片只放在内存里：题目和解答写在一起，一张纸写不下就按顺序拍好几张
  late final PhotoSet problemPhotos = PhotoSet(_problemPhotosChanged, fingerprint: true);
  late final PhotoSet redoPhotos = PhotoSet(() => _changed(archive: false)); // 订正时拍的

  Treasure? get lastTreasure => _lastTreasure;
  Treasure? _lastTreasure; // 刚拿到的宝藏（显示用）
  int? levelUp; // 刚升到第几级（没升级为空）
  bool photoMode = false; // Boss 战用拍照订正（从怪兽屋点"订正"进来时）

  /// 拍的题以前分析过：先问 Benny 是不是这道，是就直接打开以前的，不调用 GPT
  HuntSummary? seenBefore;
  bool _skipSeenCheck = false;

  BusyState? busy;
  HuntError? error;
  String? trainingError; // 后台生成修炼内容失败的原因
  CancelToken? _foreground;
  Future<void>? _trainingLoad;
  Timer? _saveTimer;
  bool _disposed = false;

  String kpName(String id) => kb.byId[id]?.label ?? id;
  List<String> get missingKps => [for (final m in (session.analysis?['missing_kps'] as List? ?? [])) (m as Map)['kp_id'] as String];
  bool get trainingLoading => _trainingLoad != null;

  void _changed({bool archive = true}) {
    if (!session.isVillage) SessionStore.save(session); // "上次没打完的错题"单独记一份，首页可以接着打
    if (archive) _scheduleArchive();
    if (!_disposed) notifyListeners();
  }

  /// 存档：改动停下 2 秒后保存一次
  bool get _archivable => !session.demo && (session.isVillage ? session.trainingReady : session.readable);

  void _scheduleArchive() {
    if (!_archivable) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _archiveNow);
  }

  Future<void> _archiveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_archivable) return;
    try {
      await (session.isVillage ? _db.saveVillage(session) : _db.saveHunt(session));
    } catch (_) {
      // 存不进去（比如空间满了）就等下次改动再存
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _foreground?.cancel();
    for (final k in _coaches.values) {
      k.dispose();
    }
    if (_saveTimer != null) unawaited(_archiveNow());
    super.dispose();
  }

  AiService _needAi() {
    final ai = this.ai;
    if (ai == null) throw AiException('not_connected', tr('還沒登入 ChatGPT。請在設定裡登入。', 'Not signed in to ChatGPT. Please sign in in Settings.', 'No has iniciado sesión en ChatGPT. Inicia sesión en Ajustes.'));
    return ai;
  }

  /// 前台等待：显示等待层，可以取消
  Future<T?> _wait<T>(String label, Future<T> Function(CancelToken token) run, {Future<void> Function()? retry}) async {
    final token = CancelToken();
    _foreground = token;
    busy = BusyState(label);
    error = null;
    if (!_disposed) notifyListeners();
    try {
      return await Future.any([run(token), token.whenCancelled.then<T>((_) => throw AiException('cancelled', tr('已取消', 'Cancelled', 'Cancelado')))]);
    } on AiException catch (e) {
      if (e.code != 'cancelled') error = HuntError(e.message, e.code, retry);
      return null;
    } catch (e) {
      error = HuntError(tr('出了點問題：$e', 'Something went wrong: $e', 'Algo salió mal: $e'), 'unknown', retry);
      return null;
    } finally {
      busy = null;
      _foreground = null;
      _changed(archive: false);
    }
  }

  void cancelBusy() => _foreground?.cancel();

  void dismissError() {
    error = null;
    notifyListeners();
  }

  // ---------- 拍题 → 分析（第 1 次调用 GPT） ----------
  void setStatus(String s) {
    session.status = s;
    _changed(archive: false);
  }

  void setNote(String s) => session.note = s;

  // 题目照片的旧接口（测试和拍题页用）
  List<Uint8List> get photos => problemPhotos.items;
  void addPhotos(List<Uint8List> list) => problemPhotos.add(list);
  void replacePhoto(int i, Uint8List bytes) => problemPhotos.replace(i, bytes);
  void removePhoto(int i) => problemPhotos.remove(i);
  void movePhotoUp(int i) => problemPhotos.moveUp(i);

  void _problemPhotosChanged() {
    seenBefore = null;
    _skipSeenCheck = false;
    _changed(archive: false);
  }

  /// 怪兽屋里分析成功过的题（用来认出拍过的题）
  Future<List<HuntSummary>> _archive() async {
    try {
      return (await _db.listHunts(limit: 200)).where((h) => h.pid != session.pid && h.stage != 'capture').toList();
    } catch (_) {
      return []; // 没网就当没拍过
    }
  }

  void _showSeen(HuntSummary h) {
    seenBefore = h;
    if (!_disposed) notifyListeners();
  }

  /// "不是这道题"：照常分析（不再带做过的题目清单）
  Future<void> analyzeAnyway() async {
    _skipSeenCheck = true;
    seenBefore = null;
    await analyze();
  }

  bool get canAnalyze => session.status.isNotEmpty && (session.demo || problemPhotos.items.isNotEmpty);

  /// 分析一道题。先认一认是不是以前拍过的：
  ///   1. 照片指纹接近 → 直接问"是不是这道"，不调用 GPT
  ///   2. 把做过的题目一起发给 GPT，它认出是同一道就只回编号（很快），也问"是不是这道"
  Future<void> analyze() async {
    final hashes = session.demo ? <String>[] : await problemPhotos.fingerprints();
    var known = <HuntSummary>[];
    var archive = <HuntSummary>[];
    if (!session.demo && !_skipSeenCheck) {
      archive = await _wait(tr('小加和小減在怪獸屋裡找找，這隻怪獸以前是不是抓到過…', 'Plus and Minus are checking the Monster House — have we caught this one before?', 'Más y Menos están buscando en la Casa de los Monstruos: ¿ya atrapamos a este?'), (_) => _archive()) ?? [];
      final seen = hashes.isEmpty ? null : archive.where((h) => samePhotos(hashes, h.photoHashes)).firstOrNull;
      if (seen != null) return _showSeen(seen);
      known = archive.where((h) => h.problemText.trim().isNotEmpty).take(maxKnown).toList();
    }
    final data = await _wait(
      tr('小加和小減正在研究這隻怪獸…', 'Plus and Minus are studying this monster…', 'Más y Menos están estudiando a este monstruo…'),
      (t) => _needAi().task('analyze', {
        'images': [for (final b in problemPhotos.items) imageDataUrl(b)],
        'status': session.status,
        'note': session.note,
        'knownProblems': [for (final (i, h) in known.indexed) {'id': 'P${i + 1}', 'text': h.problemText}],
      }, demo: session.demo, token: t),
      retry: analyze,
    );
    if (data == null) return;
    final dup = RegExp(r'^P(\d+)$').firstMatch('${data['duplicate_of'] ?? ''}');
    if (dup != null) {
      final i = int.parse(dup[1]!) - 1;
      if (i >= 0 && i < known.length) return _showSeen(known[i]);
    }
    session
      ..analysis = data
      ..queue = data['readable'] == true ? missingKps : []
      ..kpIndex = 0
      ..lessons.clear()
      ..boss = QResult()
      ..selfCheck = null
      ..photoHashes = hashes
      ..monster = _newMonster(data, archive)
      ..stage = 'analysis';
    trainingError = null;
    _changed();
    if (session.readable) {
      unawaited(_archiveNow());
      _reportAnalyzed();
      if (session.queue.isNotEmpty) unawaited(loadTraining().catchError((_) {}));
    }
  }

  /// 给这只错题怪兽起名字、定样子：用 GPT 挑的形容词，和怪兽屋里已有的重名就换一个组合
  Map<String, dynamic>? _newMonster(Map<String, dynamic> data, List<HuntSummary> archive) {
    if (data['readable'] != true) return null;
    final m = data['monster'] as Map?;
    return MonsterTraits.unique(
      errorType: '${(data['error'] as Map?)?['type'] ?? '无错误'}',
      key: session.pid,
      personality: m?['personality'] as String?,
      look: m?['look'] as String?,
      color: m?['color'] as String?,
      intro: '${m?['intro'] ?? ''}',
      taken: {for (final h in archive) ?h.monster?['name'] as String?},
    ).toJson();
  }

  void retakePhotos() {
    problemPhotos.clear();
    session.stage = 'capture';
    _changed(archive: false);
  }

  // ---------- 修炼内容（第 2 次调用 GPT，分析完就在后台开始） ----------
  /// 一次生成全部知识点的修炼内容。已经有了就不再调用。
  Future<void> loadTraining() {
    if (session.trainingReady) return Future.value();
    return _trainingLoad ??= () async {
      trainingError = null;
      if (!_disposed) notifyListeners();
      try {
        final a = session.analysis;
        final reasons = {for (final m in (a?['missing_kps'] as List? ?? []).cast<Map>()) m['kp_id']: m['reason']};
        final data = await _needAi().task('training', {
          // 村庄修炼没有原题
          'problemText': a?['problem_text'] ?? '',
          'errorDescription': (a?['error'] as Map?)?['description'] ?? '',
          'kps': [for (final id in session.queue) {'kpId': id, 'reason': reasons[id] ?? '学生在冒险地图上自己选了这个知识点来修炼'}],
          'status': session.status, // "完全不会"时，例题和练习围绕原题出
        }, demo: session.demo);
        for (final l in (data['lessons'] as List).cast<Map>()) {
          final lesson = l.cast<String, dynamic>();
          session.lessons[lesson['kp_id'] as String] = LessonState(data: lesson);
        }
        _changed();
        unawaited(_archiveNow());
      } on AiException catch (e) {
        trainingError = e.message;
        _changed(archive: false);
        rethrow;
      } finally {
        _trainingLoad = null;
      }
    }();
  }

  /// 修炼内容还没好：前台等它（后台已经在生成的话就接着等那一次）
  Future<void> waitForTraining() async {
    if (session.trainingReady) return;
    await _wait(tr('小加和小減正在準備修煉內容…', 'Plus and Minus are preparing your training…', 'Más y Menos están preparando tu entrenamiento…'), (_) => loadTraining(), retry: waitForTraining);
  }

  void startLearning() {
    session
      ..stage = 'learn'
      ..kpIndex = 0;
    _changed();
    if (!session.trainingReady) unawaited(waitForTraining());
  }

  void openKp(int i) {
    if (i < 0 || i >= session.queue.length) return;
    session.kpIndex = i;
    _changed();
  }

  void setTab(String tab) {
    session.currentLesson?.tab = tab;
    _changed();
  }

  void nextExampleStep() {
    session.currentLesson?.exStep += 1;
    _changed();
  }

  // ---------- 打小怪：输入答案，App 比对；每只小怪只打一次 ----------
  void openQuestion(int i) {
    final l = session.currentLesson;
    if (l == null || i < 0 || i >= l.practice.length) return;
    l.q = i;
    _changed();
  }

  void submitTyped(String text) {
    final l = session.currentLesson!;
    final i = l.q;
    final q = l.practice[i];
    final r = l.resultOf(i);
    if (text.trim().isEmpty || r.done) return;
    r.last = text.trim();
    r.tries += 1;
    if (checkAnswer(r.last, [for (final a in q['accepted_answers'] as List) '$a'], '${q['answer_type']}')) {
      r.correct = true;
    } else if (r.tries >= 2) {
      r.revealed = true;
      unawaited(_jailPractice(l, i)); // 答错两次：这只小怪关进监狱，一步一步学会它
    }
    _afterAnswer(l, i);
  }

  void hint() {
    final l = session.currentLesson!;
    final r = l.resultOf(l.q);
    r.hints = (r.hints + 1).clamp(0, 2);
    _changed();
  }

  /// 放弃这只小怪：不直接给答案，关进监狱，一步一步来
  Future<void> reveal() async {
    final l = session.currentLesson!;
    final i = l.q;
    l.resultOf(i).revealed = true;
    _afterAnswer(l, i);
    final k = await _jailPractice(l, i);
    await k?.start();
  }

  void skip() {
    final l = session.currentLesson!;
    l.resultOf(l.q).skipped = true;
    _afterAnswer(l, l.q);
  }

  /// "我的写法不同，其实是对的"（只给表达式、方程这类可能写法不同的题）
  void markOverride() {
    final l = session.currentLesson!;
    l.resultOf(l.q).override = true;
    _changed();
  }

  /// 在怪兽屋里用同样的题再打一遍（不调用 GPT）
  void retryLesson() {
    session.currentLesson?.restart();
    _changed();
  }

  void _afterAnswer(LessonState l, int i) {
    final r = l.resultOf(i);
    if (r.done && !r.reported) {
      r.reported = true;
      if (r.correct && !r.revealed) _independentWin(JailCase.practiceId(session.pid, l.kpId, i));
      _report('practice.graded', {
        'pid': session.pid,
        'kpId': l.kpId,
        'round': l.round,
        'level': levels.contains(l.practice[i]['level']) ? l.practice[i]['level'] : '提高',
        'mode': '输入',
        'correct': r.correct,
        'revealed': r.revealed,
        'skipped': r.skipped,
        'hints': r.hints,
        'processIssue': false,
        'errorType': null,
      });
    }
    if (l.finished && !l.reported) {
      l.reported = true;
      final s = l.score();
      _report('lesson.finished', {
        'pid': session.pid, 'kpId': l.kpId, 'round': l.round, 'right': s.right, 'total': s.total, 'passed': s.passed,
      });
      unawaited(_awardTraining());
    }
    _changed();
  }

  // ---------- 宝藏：每只怪兽（每个村庄）只有一件，只能拿一次 ----------
  bool _awarding = false;

  /// 还要修炼完几个知识点才能拿到宝藏
  int get lessonsLeft => session.queue.where((k) => !(session.lessons[k]?.finished ?? false)).length;

  /// 第一次把修炼全部打完：怪兽掉下它的宝藏。稀有度看所有修炼里最差的那个；
  /// 名字和来历用 GPT 起的（第一件能用的），没有就 App 组合。之后再打、订正都不再给。
  Future<void> _awardTraining() async {
    if (session.queue.isEmpty || lessonsLeft > 0) return;
    final ls = [for (final k in session.queue) session.lessons[k]!];
    await _award((owned) {
      final id = '${session.pid}/treasure';
      final source = session.isVillage ? 'village' : 'lesson';
      final rarity = huntRarity(ls);
      for (final l in ls) {
        final t = fromGpt(id: id, spec: (l.data['treasure'] as Map?)?.cast<String, dynamic>(), rarity: rarity, source: source);
        if (t != null) return t;
      }
      final stats = [for (final l in ls) moduleStat[kb.byId[l.kpId]?.module] ?? 'calc'];
      return procedural(id: id, rarity: rarity, statIds: stats, source: source, owned: owned);
    }, kpId: ls.length == 1 ? ls.first.kpId : null);
  }

  /// 不用修炼的题（本来就做对了、没有缺的知识点）：第一次打赢 Boss 时怪兽掉下它的宝藏
  Future<void> _awardBoss() => _award((owned) {
        final m = session.monsterTraits;
        final g = GameData.instance;
        final b = session.boss;
        final clean = (b.counted && b.tries == 1 && !b.override) || session.recheck?['verdict'] == '全对';
        return procedural(
          id: '${session.pid}/treasure',
          rarity: clean ? 'epic' : 'rare',
          statIds: ['brave', errorStat[session.errorType] ?? 'focus'],
          source: 'boss',
          owned: owned,
          name: tr('${m.displayName}的${g.word(g.drops[m.seed % g.drops.length])}', "${m.displayName}'s ${g.word(g.drops[m.seed % g.drops.length])}", '${g.word(g.drops[m.seed % g.drops.length])} de ${m.displayName}'),
          story: tr('打敗${m.displayName}掉下來的，還留著一點${g.word(m.personality)}的氣息。',
              'Dropped by the ${m.displayName}. It still feels a little ${g.word(m.personality).toLowerCase()}.', 'Lo soltó ${m.displayName}. Todavía se nota un poco ${g.word(m.personality).toLowerCase()}.'),
        );
      });

  Future<void> _award(Treasure Function(Set<String> owned) make, {String? kpId}) async {
    if (_awarding || session.treasureTaken) return;
    _awarding = true;
    try {
      final player = await PlayerStore.load();
      if (player.tookFrom(session.pid)) return; // 旧版本已经从这只怪兽拿过宝藏
      final t = make(player.names);
      session.treasure = t.toJson();
      await _gain(t, kpId: kpId);
    } finally {
      _awarding = false;
    }
  }

  Future<void> _gain(Treasure t, {String? kpId}) async {
    _lastTreasure = t;
    levelUp = null;
    if (!session.demo) {
      _report('treasure.found', {'pid': session.pid, 'kpId': kpId, 'treasure': t.toEvent()});
      final (before, after) = await PlayerStore.add(Treasure.fromJson({...t.toJson(), 'at': DateTime.now().millisecondsSinceEpoch}));
      if (after.level > before.level) levelUp = after.level;
    }
    _changed();
  }

  /// 下一只小怪；最后一只打完停在战果
  void nextQuestion() {
    final l = session.currentLesson!;
    if (l.q + 1 < l.practice.length) l.q += 1;
    _changed();
  }

  void nextKp() {
    if (session.isVillage) return; // 村庄修炼只有一个知识点，打完就回地图
    if (session.kpIndex + 1 < session.queue.length) {
      session.kpIndex += 1;
    } else {
      session.stage = 'boss';
    }
    _changed();
  }

  void goToBoss() {
    session.stage = 'boss';
    _changed();
  }

  void backToLearning() {
    if (session.queue.isEmpty) return;
    session.stage = 'learn';
    _changed();
  }

  // ---------- Boss 战：重做原题，输入最终答案，App 比对 ----------
  List<String> get learnedKps => session.queue.isNotEmpty
      ? session.queue
      : [for (final k in session.analysis?['knowledge_points'] as List? ?? []) (k as Map)['kp_id'] as String];

  void submitBoss(String text) {
    final a = session.analysis!;
    final r = session.boss;
    if (text.trim().isEmpty || r.done) return;
    r.last = text.trim();
    r.tries += 1;
    if (checkAnswer(r.last, [for (final x in a['accepted_answers'] as List) '$x'], '${a['answer_type']}')) {
      r.correct = true;
    } else if (r.tries >= 2) {
      r.revealed = true;
      unawaited(_jailBossQuietly());
    }
    _afterBoss();
  }

  /// 放弃原题：Boss 战算输，不直接给答案，关进监狱，一步一步来
  Future<void> giveUpBoss() async {
    if (session.bossCheckable) {
      session.boss.revealed = true;
    } else {
      session.selfCheck ??= false;
    }
    _afterBoss();
    final k = await _jailBoss();
    await k?.start();
  }

  /// 原题答错两次（或者对照下来没做对）：关进监狱，等他点"一步一步学会它"
  Future<void> _jailBossQuietly() async => _jailBoss();

  void markBossOverride() {
    session.boss.override = true;
    _afterBoss();
  }

  /// 原题没法自动比对：对照标准解法自己判断
  void selfCheckBoss(bool correct) {
    session.selfCheck = correct;
    _afterBoss();
    if (!correct) unawaited(_jailBossQuietly());
  }

  void _afterBoss() {
    if (session.bossDone && !session.bossReported) {
      session.bossReported = true;
      if (session.boss.correct && !session.boss.revealed) _independentWin(JailCase.bossId(session.pid));
      _report('redo.checked', {'pid': session.pid, 'isCorrect': session.bossWon, 'kpChecks': <Map<String, dynamic>>[]});
      if (session.bossWon && session.queue.isEmpty) unawaited(_awardBoss());
    }
    _changed();
  }

  /// 再打一次 Boss（重做原题、订正）
  void retryBoss() {
    session
      ..boss = QResult()
      ..selfCheck = null
      ..bossReported = false
      ..recheck = null
      ..bossRound += 1
      ..stage = 'boss';
    redoPhotos.clear();
    _changed();
  }

  bool get canRecheck => redoPhotos.items.isNotEmpty || session.demo;

  /// 拍照订正：GPT 看过程和最终答案；App 再拿最终答案和标准答案比一遍（规则在代码里）
  Future<void> submitRecheck() async {
    final a = session.analysis!;
    final data = await _wait(
      tr('小加和小減正在看你的訂正…', 'Plus and Minus are checking your correction…', 'Más y Menos están revisando tu corrección…'),
      (t) => _needAi().task('recheck', {
        'images': [for (final b in redoPhotos.items) imageDataUrl(b)],
        'problemText': a['problem_text'],
        'correctAnswer': a['correct_answer'],
        'solutionSteps': a['solution_steps'],
      }, demo: session.demo, token: t),
      retry: submitRecheck,
    );
    if (data == null) return;
    final seen = (data['final_answer_seen'] as String?)?.trim();
    final verdict = data['verdict'];
    var ok = verdict == '全对' || verdict == '答案对但过程有问题';
    var mismatch = false;
    if (ok && session.bossCheckable && seen != null && seen.isNotEmpty) {
      ok = checkAnswer(seen, [for (final x in a['accepted_answers'] as List) '$x'], '${a['answer_type']}');
      mismatch = !ok;
    }
    session.recheck = {...data, 'ok': ok, 'mismatch': mismatch};
    if (verdict != '看不清') {
      final r = session.boss;
      r.tries += 1;
      if (seen != null) r.last = seen;
      if (ok) r.correct = true;
    }
    redoPhotos.clear();
    _afterBoss();
  }

  void finish() {
    session.stage = 'victory';
    _changed();
  }

  // ---------- 怪兽监狱：放弃过的题一步一步学会，关进监狱重点看管 ----------
  final Map<String, CoachController> _coaches = {};
  final Set<String> _jailing = {};

  /// 这道题（原题 / 第几只小怪）一步一步来的控制器；还没放弃过就是 null
  CoachController? coachFor(String id) {
    final j = session.cases[id];
    if (j == null) return null;
    return _coaches[id] ??= CoachController(c: JailCase.fromJson(j), ai: ai, demo: session.demo, save: _saveCase);
  }

  CoachController? get bossCoach => session.analysis == null ? null : coachFor(JailCase.bossId(session.pid));
  CoachController? practiceCoach(LessonState l, int i) => coachFor(JailCase.practiceId(session.pid, l.kpId, i));

  void _saveCase(JailCase c) {
    session.cases[c.id] = c.toJson();
    _changed();
    if (!session.demo) unawaited(_db.saveJail(c).catchError((_) {}));
  }

  /// 打开这道题时，把监狱里的最新进度拿回来（在监狱里提审过，打怪存档里那份就旧了）
  Future<void> refreshCases() async {
    if (session.demo || session.cases.isEmpty) return;
    for (final id in session.cases.keys.toList()) {
      try {
        final fresh = await _db.getJail(id);
        if (fresh != null) session.cases[id] = fresh.toJson();
      } catch (_) {
        return; // 没网就用存档里的
      }
    }
    for (final k in _coaches.values) {
      k.dispose();
    }
    _coaches.clear();
    _changed(archive: false);
  }

  /// 关进监狱：第一次放弃就新建；以前放弃过（又放弃一次）就重新一步一步来，步骤不用再拆
  Future<CoachController?> _jail(String id, JailCase Function() make) async {
    if (!_jailing.add(id)) return null;
    try {
      final old = coachFor(id);
      if (old != null) {
        if (old.c.at > 0 && !old.c.coachDone && !old.c.freed) {
          // 正在一步一步来：接着来，只记一次放弃
          old.c.fails += 1;
          _saveCase(old.c);
          return old;
        }
        old.gaveUpAgain();
        return old;
      }
      JailCase? prev;
      if (!session.demo) prev = await _db.getJail(id).catchError((_) => null);
      final c = prev ?? make();
      if (prev != null) c.gaveUpAgain();
      _saveCase(c);
      return coachFor(id);
    } finally {
      _jailing.remove(id);
    }
  }

  Future<CoachController?> _jailBoss() {
    final a = session.analysis!;
    return _jail(JailCase.bossId(session.pid), () => JailCase(
          id: JailCase.bossId(session.pid),
          pid: session.pid,
          source: 'boss',
          problem: session.problemText,
          answerType: '${a['answer_type'] ?? '其他'}',
          accepted: [for (final x in a['accepted_answers'] as List? ?? []) '$x'],
          correctAnswer: '${a['correct_answer'] ?? ''}',
          solution: [for (final x in a['solution_steps'] as List? ?? []) '$x'],
          monster: session.monsterTraits.toJson(),
        ));
  }

  Future<CoachController?> _jailPractice(LessonState l, int i) {
    final q = l.practice[i];
    final id = JailCase.practiceId(session.pid, l.kpId, i);
    final accepted = [for (final x in q['accepted_answers'] as List? ?? []) '$x'];
    final options = [for (final x in q['options'] as List? ?? []) '$x'];
    // 选择题的正确答案写成"B. 选项内容"，拆步骤时 GPT 才知道选的是什么
    final letter = accepted.isEmpty ? '' : accepted.first.trim();
    final idx = 'ABCD'.indexOf(letter);
    final correct = q['answer_type'] == '选择' && idx >= 0 && idx < options.length ? '$letter. ${options[idx]}' : (accepted.isEmpty ? '' : accepted.first);
    return _jail(id, () => JailCase(
          id: id,
          pid: session.pid,
          source: 'practice',
          kpId: l.kpId,
          level: '${q['level'] ?? ''}',
          problem: '${q['problem'] ?? ''}',
          answerType: '${q['answer_type'] ?? '其他'}',
          accepted: accepted,
          correctAnswer: correct,
          solution: [for (final x in q['solution_steps'] as List? ?? []) '$x'],
          options: options,
        ));
  }

  /// 关在监狱里的题，在打怪页面里再打一遍时自己做对了：和提审一样算刑期（关进来的当天、同一天第二次不算）
  void _independentWin(String id) {
    final k = coachFor(id);
    if (k == null || !k.c.coachDone || k.c.freed) return;
    if (k.c.recordWin(DateTime.now().millisecondsSinceEpoch)) _saveCase(k.c);
  }

  /// 小怪答错两次以后点"一步一步学会它"
  Future<void> coachPractice() async {
    final l = session.currentLesson!;
    final k = practiceCoach(l, l.q) ?? await _jailPractice(l, l.q);
    await k?.start();
  }

  /// 原题输了以后点"一步一步学会它"
  Future<void> coachBoss() async {
    final k = bossCoach ?? await _jailBoss();
    await k?.start();
  }

  // ---------- 学习事件（示例模式不记） ----------
  void _reportAnalyzed() {
    if (session.analyzedReported) return;
    session.analyzedReported = true;
    final a = session.analysis!;
    final err = (a['error'] as Map).cast<String, dynamic>();
    final text = '${a['problem_text']}';
    _report('problem.analyzed', {
      'pid': session.pid,
      'status': session.status.isEmpty ? null : session.status,
      'problemText': text.length > 3000 ? text.substring(0, 3000) : text,
      'studentAnswer': a['student_answer'],
      'isCorrect': a['is_correct'],
      'correctAnswer': '${a['correct_answer']}',
      'error': {'step': err['step'], 'type': err['type'], 'description': '${err['description']}'},
      'knowledgePoints': [
        for (final k in a['knowledge_points'] as List) {'kpId': (k as Map)['kp_id'], 'role': k['role'], 'judgement': k['judgement']},
      ],
      'missingKps': missingKps,
    });
  }

  void _report(String type, Map<String, dynamic> payload) {
    if (session.demo) return;
    unawaited(_db.record(type, payload).catchError((_) {}));
  }
}


/// 一组按顺序拍的照片（只放在内存里）；fingerprint 时拍完就在后台算照片指纹
class PhotoSet {
  PhotoSet(this._onChanged, {this.fingerprint = false});
  final void Function() _onChanged;
  final bool fingerprint;
  final List<Uint8List> _items = [];
  final Map<Uint8List, Future<String?>> _hashes = {};

  List<Uint8List> get items => List.unmodifiable(_items);

  void add(List<Uint8List> list) {
    for (final b in list.take(maxPhotos - _items.length)) {
      _items.add(b);
      if (fingerprint) _hashes[b] = photoHash(b);
    }
    _onChanged();
  }

  void replace(int i, Uint8List bytes) {
    _hashes.remove(_items[i]);
    _items[i] = bytes;
    if (fingerprint) _hashes[bytes] = photoHash(bytes);
    _onChanged();
  }

  void remove(int i) {
    _hashes.remove(_items.removeAt(i));
    _onChanged();
  }

  /// 把第 i 张往前挪一位（拍乱了顺序时）
  void moveUp(int i) {
    if (i <= 0 || i >= _items.length) return;
    _items.insert(i - 1, _items.removeAt(i));
    _onChanged();
  }

  void clear() {
    _items.clear();
    _hashes.clear();
  }

  Future<List<String>> fingerprints() async => [for (final b in _items) ?await (_hashes[b] ??= photoHash(b))];
}
