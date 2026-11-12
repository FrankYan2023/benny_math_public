import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/monster.dart';

/// 一次"打怪"（处理一道错题）的全部内容和进度。照片不在这里，只在内存里。
/// 也用来装"村庄修炼"：在冒险地图上点开一个知识点直接修炼，这时 village 是知识点编号，没有原题和 Boss 战。
/// GPT 返回的 JSON（分析、修炼内容）原样保存为 Map，格式由 ai_tasks.dart 的 schema 保证。
/// 整份存档存在本机数据库里，以后打开这道题直接读，不再调用 GPT。

const levels = ['基础', '变式', '提高', '挑战'];
const hardLevels = ['提高', '挑战'];
const errorTypes = ['计算失误', '概念不清', '方法不会', '审题错误', '前置缺失', '未作答', '无错误'];

/// 一道题（练习题或重做原题）的作答情况：输入答案，App 自己比对；答错两次就给出答案
class QResult {
  QResult({
    this.tries = 0,
    this.correct = false,
    this.hints = 0,
    this.revealed = false,
    this.skipped = false,
    this.override = false,
    this.last = '',
    this.reported = false,
  });

  int tries;
  bool correct;
  int hints;
  bool revealed;
  bool skipped;
  bool override; // "写法不同，其实是对的"
  String last;
  bool reported; // 已经记进学习事件

  bool get done => correct || revealed || skipped || override;
  bool get counted => (correct && !revealed) || override;

  Map<String, dynamic> toJson() => {
        'tries': tries, 'correct': correct, 'hints': hints, 'revealed': revealed, 'skipped': skipped,
        'override': override, 'last': last, 'reported': reported,
      };

  factory QResult.fromJson(Map<String, dynamic> j) => QResult(
        tries: j['tries'] as int? ?? 0,
        correct: j['correct'] as bool? ?? false,
        hints: j['hints'] as int? ?? 0,
        revealed: j['revealed'] as bool? ?? false,
        skipped: j['skipped'] as bool? ?? false,
        override: j['override'] as bool? ?? false,
        last: j['last'] as String? ?? '',
        reported: j['reported'] as bool? ?? false,
      );
}

class Score {
  const Score(this.right, this.total, this.need, this.passed);
  final int right;
  final int total;
  final int need;
  final bool passed;
}

/// 一个知识点的修炼：讲解、例题、4 只小怪，三个标签随时切换。小怪只打一次。
class LessonState {
  LessonState({
    required this.data,
    this.tab = 'card',
    this.exStep = 1,
    this.q = 0,
    this.round = 1,
    Map<int, QResult>? results,
    this.reported = false,
    this.treasure,
  }) : results = results ?? {};

  Map<String, dynamic> data;
  String tab; // card / example / practice
  int exStep; // 例题显示到第几步
  int q; // 正在打第几只小怪
  int round; // 第几遍（在怪兽屋里可以用同样的题再打一遍）
  Map<int, QResult> results;
  bool reported; // 修炼结果已经上报
  Map<String, dynamic>? treasure; // 旧版本：每个修炼打完都有一件（现在一只怪兽只有一件，见 HuntSession.treasure）

  String get kpId => '${data['kp_id']}';
  Map<String, dynamic> get card => (data['card'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get example => (data['example'] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> get practice => [for (final p in data['practice'] as List) (p as Map).cast<String, dynamic>()];

  QResult resultOf(int i) => results.putIfAbsent(i, QResult.new);

  /// 用同样的 4 只小怪再打一遍（不调用 GPT）
  void restart() {
    results.clear();
    q = 0;
    reported = false;
    round = round >= 20 ? 20 : round + 1;
    tab = 'practice';
  }
  bool get finished => practice.isNotEmpty && [for (var i = 0; i < practice.length; i++) results[i]?.done ?? false].every((d) => d);
  int get defeated => [for (var i = 0; i < practice.length; i++) results[i]?.counted ?? false].where((x) => x).length;

  /// 过关规则（App 判定，不交给 GPT）：答对 ≥ 75%，并且提高题或挑战题里至少 1 道不看提示就答对
  Score score() {
    final qs = [for (var i = 0; i < practice.length; i++) if (!(results[i]?.skipped ?? false)) i];
    final right = qs.where((i) => results[i]?.counted ?? false).length;
    final hard = qs.where((i) => hardLevels.contains(practice[i]['level']));
    final hardOk = hard.any((i) {
      final r = results[i];
      return r != null && r.counted && r.hints == 0;
    });
    final need = (qs.length * 0.75).ceil();
    return Score(right, qs.length, need, qs.isNotEmpty && right >= need && (hard.isEmpty || hardOk));
  }

  Map<String, dynamic> toJson() => {
        'data': data, 'tab': tab, 'exStep': exStep, 'q': q, 'round': round, 'treasure': treasure,
        'results': {for (final e in results.entries) '${e.key}': e.value.toJson()},
        'reported': reported,
      };

  factory LessonState.fromJson(Map<String, dynamic> j) => LessonState(
        data: (j['data'] as Map).cast<String, dynamic>(),
        tab: j['tab'] as String? ?? 'card',
        exStep: j['exStep'] as int? ?? 1,
        q: j['q'] as int? ?? 0,
        round: j['round'] as int? ?? 1,
        results: {
          for (final e in (j['results'] as Map? ?? {}).entries) int.parse(e.key as String): QResult.fromJson((e.value as Map).cast<String, dynamic>()),
        },
        reported: j['reported'] as bool? ?? false,
        treasure: (j['treasure'] as Map?)?.cast<String, dynamic>(),
      );
}

class HuntSession {
  HuntSession({
    required this.pid,
    this.demo = false,
    this.village,
    int? createdAt,
    this.stage = 'capture',
    this.status = '',
    this.note = '',
    this.analysis,
    List<String>? queue,
    this.kpIndex = 0,
    Map<String, LessonState>? lessons,
    QResult? boss,
    this.selfCheck,
    this.analyzedReported = false,
    this.bossReported = false,
    List<String>? photoHashes,
    this.monster,
    this.bossRound = 1,
    this.bossTreasure,
    this.recheck,
    this.treasure,
    Map<String, Map<String, dynamic>>? cases,
  })  : cases = cases ?? {},
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        photoHashes = photoHashes ?? [],
        queue = queue ?? [],
        lessons = lessons ?? {},
        boss = boss ?? QResult();

  final String pid;
  final bool demo;
  final String? village; // 村庄修炼：知识点编号；错题打怪时为空
  final int createdAt;
  String stage; // capture / analysis / learn / boss / victory
  String status; // 完全不会 / 做了但不确定对不对 / 做错了
  String note;
  Map<String, dynamic>? analysis;
  List<String> queue; // 要修炼的知识点（顺序）
  int kpIndex; // 正在看第几个知识点
  Map<String, LessonState> lessons; // 修炼内容：一次生成好，全部保存
  QResult boss; // Boss 战：重做原题，输入最终答案
  bool? selfCheck; // 原题没法自动比对时，自己对照解法判断做对没有
  bool analyzedReported;
  bool bossReported;
  List<String> photoHashes; // 照片指纹，用来认出以前拍过的题
  Map<String, dynamic>? monster; // 这只错题怪兽的样子和名字（MonsterTraits）
  int bossRound; // 第几次打 Boss（订正可以打好几次）
  Map<String, dynamic>? bossTreasure; // 旧版本：打赢 Boss 掉的宝藏
  Map<String, dynamic>? recheck; // 最近一次拍照订正的结果
  Map<String, dynamic>? treasure; // 这只怪兽（这个村庄）唯一的一件宝藏，拿到以后不会再给
  Map<String, Map<String, dynamic>> cases; // 放弃过的题（原题、小怪）：一步一步来的进度，按监狱编号存（JailCase），监狱存档里也有一份

  /// 这只怪兽的宝藏；旧存档里每个修炼、每次 Boss 都有一件，取第一件
  Map<String, dynamic>? get monsterTreasure => treasure ?? [for (final id in queue) ?lessons[id]?.treasure, ?bossTreasure].firstOrNull;
  bool get treasureTaken => monsterTreasure != null;

  /// 这只怪兽（旧的题没有存，就按题目编号算出一只，每次都一样）
  MonsterTraits get monsterTraits => MonsterTraits.fromJson(monster) ?? MonsterTraits.fromSeed(pid, errorType);

  String? get currentKp => kpIndex < queue.length ? queue[kpIndex] : null;
  LessonState? get currentLesson => currentKp == null ? null : lessons[currentKp];
  bool get readable => analysis?['readable'] == true;
  bool get trainingReady => queue.every(lessons.containsKey);
  String get errorType => (analysis?['error'] as Map?)?['type'] as String? ?? '无错误';
  String get problemText => '${analysis?['problem_text'] ?? ''}';
  bool get isVillage => village != null;

  /// 从冒险地图进入一个知识点的修炼
  factory HuntSession.village(String kpId) =>
      HuntSession(pid: 'village-$kpId', village: kpId, stage: 'learn', queue: [kpId]);

  /// 原题能不能自动比对答案
  bool get bossCheckable => analysis?['answer_type'] != '其他' && ((analysis?['accepted_answers'] as List?)?.isNotEmpty ?? false);
  bool get bossWon => bossCheckable ? boss.counted : selfCheck == true;
  bool get bossDone => bossCheckable ? boss.done : selfCheck != null;

  Map<String, dynamic> toJson() => {
        'pid': pid, 'demo': demo, 'village': village, 'createdAt': createdAt, 'stage': stage, 'status': status, 'note': note, 'analysis': analysis,
        'queue': queue, 'kpIndex': kpIndex, 'lessons': {for (final e in lessons.entries) e.key: e.value.toJson()},
        'boss': boss.toJson(), 'selfCheck': selfCheck, 'analyzedReported': analyzedReported, 'bossReported': bossReported,
        'photoHashes': photoHashes, 'monster': monster, 'bossRound': bossRound, 'bossTreasure': bossTreasure, 'recheck': recheck,
        'treasure': treasure, 'cases': cases,
      };

  factory HuntSession.fromJson(Map<String, dynamic> j) => HuntSession(
        pid: j['pid'] as String,
        demo: j['demo'] as bool? ?? false,
        village: j['village'] as String?,
        createdAt: j['createdAt'] as int?,
        stage: j['stage'] as String? ?? 'capture',
        status: j['status'] as String? ?? '',
        note: j['note'] as String? ?? '',
        analysis: (j['analysis'] as Map?)?.cast<String, dynamic>(),
        queue: [for (final q in j['queue'] as List? ?? []) q as String],
        kpIndex: j['kpIndex'] as int? ?? 0,
        lessons: {
          for (final e in (j['lessons'] as Map? ?? {}).entries) e.key as String: LessonState.fromJson((e.value as Map).cast<String, dynamic>()),
        },
        boss: j['boss'] is Map ? QResult.fromJson((j['boss'] as Map).cast<String, dynamic>()) : null,
        selfCheck: j['selfCheck'] as bool?,
        analyzedReported: j['analyzedReported'] as bool? ?? false,
        bossReported: j['bossReported'] as bool? ?? false,
        photoHashes: [for (final h in j['photoHashes'] as List? ?? []) '$h'],
        monster: (j['monster'] as Map?)?.cast<String, dynamic>(),
        bossRound: j['bossRound'] as int? ?? 1,
        bossTreasure: (j['bossTreasure'] as Map?)?.cast<String, dynamic>(),
        recheck: (j['recheck'] as Map?)?.cast<String, dynamic>(),
        treasure: (j['treasure'] as Map?)?.cast<String, dynamic>(),
        cases: {for (final e in (j['cases'] as Map? ?? {}).entries) e.key as String: (e.value as Map).cast<String, dynamic>()},
      );

  /// 村庄修炼的摘要（地图上用）
  Map<String, dynamic> villageSummary() {
    final l = lessons[village];
    return {'finished': l?.finished ?? false, 'defeated': l?.defeated ?? 0, 'total': l?.practice.length ?? 0};
  }

  /// 存档列表里显示的摘要
  Map<String, dynamic> summary() => {
        'problemText': problemText.length > 3000 ? problemText.substring(0, 3000) : problemText,
        'stage': stage,
        'kpIds': queue.take(10).toList(),
        'errorType': errorType,
        'photoHashes': photoHashes.take(6).toList(),
        if (analysis != null) 'monster': monsterTraits.toJson(),
        'done': stage == 'victory',
      };
}

/// 当前这道题的进度也存一份在本机：没网、或者 App 被关掉，下次打开可以接着打
abstract final class SessionStore {
  static const _key = 'hunt.v2';
  static const _old = 'hunt.v1';

  static Future<HuntSession?> load() async {
    final p = await SharedPreferences.getInstance();
    if (p.containsKey(_old)) await p.remove(_old); // 旧格式的进度不再兼容
    final s = p.getString(_key);
    if (s == null) return null;
    try {
      return HuntSession.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(HuntSession s) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(s.toJson()));

  static Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}
