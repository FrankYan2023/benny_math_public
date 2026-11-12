import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../i18n.dart';

/// 一次 AI 调用的记录
class AiCall {
  AiCall({required this.at, required this.task, required this.model, required this.ok, this.code, this.input = 0, this.output = 0, this.ms = 0});

  final int at; // 什么时候（毫秒）
  final String task; // analyze / training / check
  final String model;
  final bool ok;
  final String? code; // 失败的原因，比如 quota
  final int input; // 用掉的 token
  final int output;
  final int ms; // 用了多久

  int get tokens => input + output;

  Map<String, dynamic> toJson() => {'at': at, 'task': task, 'model': model, 'ok': ok, 'code': code, 'in': input, 'out': output, 'ms': ms};

  factory AiCall.fromJson(Map<String, dynamic> j) => AiCall(
        at: j['at'] as int,
        task: j['task'] as String? ?? '',
        model: j['model'] as String? ?? '',
        ok: j['ok'] as bool? ?? false,
        code: j['code'] as String?,
        input: j['in'] as int? ?? 0,
        output: j['out'] as int? ?? 0,
        ms: j['ms'] as int? ?? 0,
      );
}

/// ChatGPT 额度监控。
/// OpenAI 不告诉第三方应用还剩多少额度、什么时候恢复，只在用完时报错，所以这里自己记账：
/// 每次调用记下时间、token 和成功没有；额度用完时记下时间。
/// Plus 的额度是"过去 5 小时"滚动计算的，所以用完以后最晚 5 小时一定恢复。
class AiUsage {
  AiUsage._(this.calls, this.quotaAt);

  final List<AiCall> calls; // 最近 7 天，新的在后面
  final int? quotaAt; // 最近一次额度用完的时间（之后有成功的调用就清掉）

  static const window = Duration(hours: 5);
  static const _key = 'ai.usage.v1';
  static const _keep = Duration(days: 7);

  static Future<AiUsage> load({DateTime? now}) async {
    final p = await SharedPreferences.getInstance();
    try {
      final j = jsonDecode(p.getString(_key) ?? '{}') as Map<String, dynamic>;
      final from = (now ?? DateTime.now()).subtract(_keep).millisecondsSinceEpoch;
      return AiUsage._(
        [for (final c in j['calls'] as List? ?? []) AiCall.fromJson((c as Map).cast<String, dynamic>())].where((c) => c.at >= from).toList(),
        j['quotaAt'] as int?,
      );
    } catch (_) {
      return AiUsage._([], null);
    }
  }

  /// 记一次调用
  static Future<void> record(AiCall call) async {
    final u = await load();
    final calls = [...u.calls, call];
    var quotaAt = u.quotaAt;
    if (call.ok) quotaAt = null;
    if (call.code == 'quota') quotaAt = call.at;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode({'calls': [for (final c in calls.skip(calls.length > 300 ? calls.length - 300 : 0)) c.toJson()], 'quotaAt': quotaAt}));
  }

  /// 额度用完了吗（最近一次报"额度用完"之后还没有成功过，而且还没过 5 小时）
  bool exhausted({DateTime? now}) => quotaAt != null && (now ?? DateTime.now()).millisecondsSinceEpoch < quotaAt! + window.inMilliseconds;

  /// 最晚什么时候恢复
  DateTime? get recoverBy => quotaAt == null ? null : DateTime.fromMillisecondsSinceEpoch(quotaAt! + window.inMilliseconds);

  Iterable<AiCall> since(DateTime t) => calls.where((c) => c.at >= t.millisecondsSinceEpoch);

  /// 过去 5 小时用掉的 token（Plus 额度就是按这段时间算的）
  int tokensInWindow({DateTime? now}) => since((now ?? DateTime.now()).subtract(window)).fold(0, (s, c) => s + c.tokens);

  /// 今天（从 0 点起）
  Iterable<AiCall> today({DateTime? now}) {
    final n = now ?? DateTime.now();
    return since(DateTime(n.year, n.month, n.day));
  }
}

/// 额度用完时给 Benny 看的话
String quotaMessage(DateTime? recoverBy) {
  final when = recoverBy == null ? tr('過幾個小時', 'in a few hours', 'en unas horas') : tr('最晚 ${hhmm(recoverBy)}', 'by ${hhmm(recoverBy)} at the latest', 'como muy tarde a las ${hhmm(recoverBy)}');
  return tr(
    'ChatGPT 的額度暫時用完了，$when 就能恢復。已經準備好的修煉、怪獸屋裡的題、地圖上準備好的村莊都能接著用，不需要 AI。',
    'The ChatGPT quota is used up for now. It will be back $when. Trainings that are already ready, the Monster House and prepared villages still work without AI.', 'La cuota de ChatGPT se ha agotado por ahora. Volverá $when. Los entrenamientos ya preparados, la Casa de los Monstruos y las aldeas preparadas siguen funcionando sin IA.',
  );
}

String hhmm(DateTime t) {
  final now = DateTime.now();
  final day = t.day == now.day
      ? ''
      : (t.difference(DateTime(now.year, now.month, now.day)).inDays == 1 ? tr('明天 ', 'tomorrow ', 'mañana ') : tr('${t.month}月${t.day}日 ', '${t.month}/${t.day} ', '${t.day}/${t.month} '));
  return '$day${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
