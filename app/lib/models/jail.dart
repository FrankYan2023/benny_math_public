import '../logic/answer_check.dart';

/// 怪兽监狱里的一道题：Benny 放弃了、或者答错两次的题（错题原题或修炼里的小怪）。
/// 先"一步一步来"：第 1 步讲给他看；后面每一步先只给"要做什么"和提示，他在纸上做、拍照检查，
/// 对了直接看这一步的讲解，错了说明错在哪里再给他看正确的这一步，然后做下一步。最后才给出答案。
/// 学会以后关在监狱里重点看管：要在不同的两天里自己独立做对（不看步骤）才放出来（规则在代码里，不交给 GPT）。
/// 整份存在本机的监狱存档里；错题打怪存档里也带一份（HuntSession.cases）。
class JailCase {
  JailCase({
    required this.id,
    required this.pid,
    required this.source,
    required this.problem,
    required this.answerType,
    required this.accepted,
    required this.correctAnswer,
    this.kpId,
    this.level,
    List<String>? solution,
    List<String>? options,
    this.monster,
    int? since,
    this.coach,
    this.at = 0,
    List<Map<String, dynamic>>? log,
    List<int>? wins,
    this.freedAt,
    this.fails = 1,
    this.retrialTries = 0,
  })  : since = since ?? DateTime.now().millisecondsSinceEpoch,
        solution = solution ?? [],
        options = options ?? [],
        log = log ?? [],
        wins = wins ?? [];

  final String id; // 错题原题：'<pid>~boss'；小怪：'<pid>~<知识点>~<第几只>'
  final String pid;
  final String source; // boss / practice
  final String? kpId;
  final String? level; // 小怪的难度
  final String problem;
  final String answerType; // 数值 / 表达式 / 方程的解 / 选择 / 其他
  final List<String> accepted;
  final String correctAnswer;
  final List<String> solution; // 分析或修炼时给的简短解法（给 GPT 拆步骤做参考）
  final List<String> options; // 选择题的选项
  final Map<String, dynamic>? monster; // 错题怪兽（MonsterTraits 的 JSON）；小怪为空
  int since; // 关进来的时间（放出来以后又放弃，就重新关进来）
  Map<String, dynamic>? coach; // GPT 拆好的步骤：{steps: [{goal, hint, result, explain}], final_answer, idea}
  int at; // 前几步已经完成（第 at+1 步正在做）
  List<Map<String, dynamic>> log; // 每一步怎么完成的：{how: shown/right/wrong/told, seen, where, comment}
  List<int> wins; // 在监狱里自己独立做对、而且算数的时间
  int? freedAt; // 放出来的时间
  int fails; // 放弃过几次
  int retrialTries; // 这一次提审已经答了几次（输入答案最多两次）

  static const winsNeeded = 2;

  static String bossId(String pid) => '$pid~boss';
  static String practiceId(String pid, String kpId, int i) => '$pid~$kpId~$i';

  List<Map<String, dynamic>> get steps => [for (final s in coach?['steps'] as List? ?? []) (s as Map).cast<String, dynamic>()];
  bool get hasSteps => steps.isNotEmpty;
  bool get coachDone => hasSteps && at >= steps.length;
  bool get freed => freedAt != null;
  bool get checkable => answerType != '其他' && accepted.isNotEmpty;

  /// 自己做对的步数（第 1 步是讲给他看的，不算）
  int get stepsByHimself => log.where((l) => l['how'] == 'right').length;

  /// 开始（或重新）一步一步来：第 1 步直接讲给他看
  void startCoach() {
    at = steps.isEmpty ? 0 : 1;
    log = [if (steps.isNotEmpty) {'how': 'shown'}];
  }

  /// 第 at+1 步的结果：对 / 错（说明错在哪里）/ 不会（直接讲）
  void finishStep(String how, {String? seen, String? where, String? comment}) {
    if (coachDone) return;
    log = [...log.take(at), {'how': how, 'seen': ?seen, 'where': ?where, 'comment': ?comment}];
    at += 1;
  }

  // ---------- 刑期：在不同的两天里自己独立做对 ----------
  static String _day(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month}-${d.day}';
  }

  /// 今天做对算不算数：关进来的当天、已经算过一次的那天都不算（隔天再做才是真的记住了）
  bool winCountsOn(int now) => !freed && _day(now) != _day(since) && wins.every((w) => _day(w) != _day(now));

  /// 提审（自己独立重做）做对了：算数就记一次，够两次就放出来。返回这次算不算数。
  bool recordWin(int now) {
    retrialTries = 0;
    if (!winCountsOn(now)) return false;
    wins = [...wins, now];
    if (wins.length >= winsNeeded) freedAt = now;
    return true;
  }

  /// 输入的答案对不对（App 比对，不调用 GPT）
  bool check(String answer) => checkAnswer(answer, accepted, answerType);

  /// 又放弃了一次：重新关进来，重新一步一步来（步骤已经有了，不再调用 GPT 拆步骤）
  void gaveUpAgain({int? now}) {
    fails += 1;
    retrialTries = 0;
    wins = []; // 又不会了：刑期从头算
    if (freed) {
      freedAt = null;
      since = now ?? DateTime.now().millisecondsSinceEpoch;
    }
    startCoach();
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'pid': pid, 'source': source, 'kpId': kpId, 'level': level, 'problem': problem, 'answerType': answerType,
        'accepted': accepted, 'correctAnswer': correctAnswer, 'solution': solution, 'options': options, 'monster': monster,
        'since': since, 'coach': coach, 'at': at, 'log': log, 'wins': wins, 'freedAt': freedAt, 'fails': fails,
        'retrialTries': retrialTries,
      };

  factory JailCase.fromJson(Map<String, dynamic> j) => JailCase(
        id: j['id'] as String,
        pid: j['pid'] as String? ?? '',
        source: j['source'] as String? ?? 'boss',
        kpId: j['kpId'] as String?,
        level: j['level'] as String?,
        problem: j['problem'] as String? ?? '',
        answerType: j['answerType'] as String? ?? '其他',
        accepted: [for (final a in j['accepted'] as List? ?? []) '$a'],
        correctAnswer: j['correctAnswer'] as String? ?? '',
        solution: [for (final a in j['solution'] as List? ?? []) '$a'],
        options: [for (final a in j['options'] as List? ?? []) '$a'],
        monster: (j['monster'] as Map?)?.cast<String, dynamic>(),
        since: j['since'] as int?,
        coach: (j['coach'] as Map?)?.cast<String, dynamic>(),
        at: j['at'] as int? ?? 0,
        log: [for (final l in j['log'] as List? ?? []) (l as Map).cast<String, dynamic>()],
        wins: [for (final w in j['wins'] as List? ?? []) w as int],
        freedAt: j['freedAt'] as int?,
        fails: j['fails'] as int? ?? 1,
        retrialTries: j['retrialTries'] as int? ?? 0,
      );

  JailCase copy() => JailCase.fromJson(toJson());

  /// 存档里的摘要（家长报表用）
  Map<String, dynamic> summary() => {
        'pid': pid.length > 64 ? pid.substring(0, 64) : pid,
        'kpId': kpId,
        'source': source,
        'problemText': problem.length > 3000 ? problem.substring(0, 3000) : problem,
        'since': since,
        'wins': wins.take(20).toList(),
        'freedAt': freedAt,
        'fails': fails.clamp(0, 1000),
        'stepsDone': stepsByHimself.clamp(0, 20),
        'stepsTotal': steps.length.clamp(0, 20),
      };
}
