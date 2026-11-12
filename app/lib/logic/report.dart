import '../models/knowledge.dart';
import '../services/local_db.dart';
import '../theme/pixel_theme.dart';
import 'mastery.dart';

/// 家长报表的数据（从原来后端的 report.ts 搬过来，数据都读本机）：
/// 扫过哪些题、结果如何、哪些知识点没学会、错因分布、学习时长、怪兽监狱。
class ParentReport {
  ParentReport._({
    required this.from,
    required this.to,
    required this.summary,
    required this.attention,
    required this.problems,
    required this.errorTypes,
    required this.jail,
    required this.kpStatus,
  });

  final int from;
  final int to;
  final ReportSummary summary;
  final List<AttentionKp> attention; // 最需要关注的薄弱知识点（最多 10 个）
  final List<ReportProblem> problems; // 新的在前
  final List<(String, int)> errorTypes; // 错因 → 次数
  final List<Map<String, dynamic>> jail; // 监狱摘要：还关着的在前
  final Map<String, KpStatus> kpStatus; // 有记录的知识点

  int get jailLocked => jail.where((j) => j['freedAt'] == null).length;
  int get jailFreed => jail.length - jailLocked;

  static const errorOrder = ['计算失误', '概念不清', '方法不会', '审题错误', '前置缺失', '未作答', '无错误'];
  static const _day = 24 * 3600 * 1000;

  static Future<ParentReport> build(LocalDb db, Knowledge kb, {required int from, required int to}) async {
    final problems = await db.problems();
    final daily = await db.daily();
    final states = await db.rawKpStates();
    final jail = await db.jailSummaries();

    final days = <String>{for (var t = from; t <= to && t - from < 400 * _day; t += _day) dayOf(t), dayOf(to)};
    int sum(String k) => days.fold(0, (s, d) => s + (((daily[d] as Map?)?[k] as num?)?.toInt() ?? 0));
    final active = days.where((d) {
      final m = (daily[d] as Map?) ?? {};
      return [m['problems'], m['practice'], m['seconds']].any((v) => ((v as num?) ?? 0) > 0);
    }).length;

    final inRange = [
      for (final p in problems.values)
        if (((p as Map)['createdAt'] as num).toInt() >= from && (p['createdAt'] as num).toInt() <= to) p.cast<String, dynamic>(),
    ]..sort((a, b) => (b['createdAt'] as num).compareTo(a['createdAt'] as num));

    final errors = <String, int>{};
    for (final p in inRange) {
      final t = '${(p['error'] as Map?)?['type'] ?? '无错误'}';
      if (t != '无错误' && t != '未作答') errors[t] = (errors[t] ?? 0) + 1;
    }

    final weak = [
      for (final e in states.entries)
        if ((e.value as Map)['state'] == 'weak')
          AttentionKp(e.key, ((e.value as Map)['wrongCount'] as num?)?.toInt() ?? 0, (e.value as Map)['lastErrorType'] as String?,
              ((e.value as Map)['lastAt'] as num?)?.toInt() ?? 0),
    ]..sort((a, b) => b.wrongCount != a.wrongCount ? b.wrongCount.compareTo(a.wrongCount) : b.lastAt.compareTo(a.lastAt));

    return ParentReport._(
      from: from,
      to: to,
      summary: ReportSummary(
        problems: sum('problems'),
        firstTryCorrect: sum('firstTryCorrect'),
        redoTotal: sum('redos'),
        redoCorrect: sum('redoCorrect'),
        practiceRight: sum('practiceRight'),
        practiceTotal: sum('practice'),
        lessonsPassed: sum('lessonsPassed'),
        lessonsTotal: sum('lessons'),
        minutes: (sum('seconds') / 60).round(),
        activeDays: active,
      ),
      attention: weak.take(10).toList(),
      problems: [for (final p in inRange) ReportProblem.from(p, kb)],
      errorTypes: [for (final t in errorOrder) if (errors[t] != null) (t, errors[t]!)],
      jail: [...jail]..sort((a, b) {
          final fa = a['freedAt'] != null, fb = b['freedAt'] != null;
          if (fa != fb) return fa ? 1 : -1;
          return ((b['since'] as num?) ?? 0).compareTo((a['since'] as num?) ?? 0);
        }),
      kpStatus: {for (final e in states.entries) e.key: KpStatus.parse((e.value as Map)['state'] as String?)},
    );
  }
}

class ReportSummary {
  const ReportSummary({
    required this.problems,
    required this.firstTryCorrect,
    required this.redoTotal,
    required this.redoCorrect,
    required this.practiceRight,
    required this.practiceTotal,
    required this.lessonsPassed,
    required this.lessonsTotal,
    required this.minutes,
    required this.activeDays,
  });

  final int problems, firstTryCorrect, redoTotal, redoCorrect, practiceRight, practiceTotal, lessonsPassed, lessonsTotal, minutes, activeDays;
}

class AttentionKp {
  const AttentionKp(this.id, this.wrongCount, this.lastErrorType, this.lastAt);
  final String id;
  final int wrongCount;
  final String? lastErrorType;
  final int lastAt;
}

/// 报表里的一道题
class ReportProblem {
  const ReportProblem({
    required this.pid,
    required this.at,
    required this.problemText,
    required this.firstResult,
    required this.errorType,
    required this.errorDescription,
    required this.missingKps,
    required this.lessons,
    required this.redo,
  });

  final String pid;
  final int at;
  final String problemText;
  final String firstResult; // 做对了 / 做错了 / 不会做 / 没写解答
  final String errorType;
  final String errorDescription;
  final List<String> missingKps;
  final Map<String, ({bool passed, int right, int total})> lessons;
  final String redo; // 做对了 / 还不对 / 没重做 / 不用重做

  factory ReportProblem.from(Map<String, dynamic> p, Knowledge kb) {
    final correct = p['isCorrect'] as bool?;
    final redo = (p['redo'] as Map?)?.cast<String, dynamic>();
    return ReportProblem(
      pid: '${p['pid']}',
      at: (p['createdAt'] as num).toInt(),
      problemText: '${p['problemText'] ?? ''}',
      firstResult: correct == true
          ? '做对了'
          : correct == false
              ? '做错了'
              : p['status'] == '完全不会'
                  ? '不会做'
                  : '没写解答',
      errorType: '${(p['error'] as Map?)?['type'] ?? '无错误'}',
      errorDescription: '${(p['error'] as Map?)?['description'] ?? ''}',
      missingKps: [for (final k in p['missingKps'] as List? ?? []) '$k'],
      lessons: {
        for (final e in ((p['lessons'] as Map?) ?? {}).entries)
          '${e.key}': (
            passed: (e.value as Map)['passed'] == true,
            right: ((e.value as Map)['right'] as num?)?.toInt() ?? 0,
            total: ((e.value as Map)['total'] as num?)?.toInt() ?? 0,
          ),
      },
      redo: redo != null ? (redo['isCorrect'] == true ? '做对了' : '还不对') : (correct == true ? '不用重做' : '没重做'),
    );
  }
}
