import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/knowledge.dart';
import 'ai_service.dart';
import 'ai_tasks.dart';
import 'ai_usage.dart';
import '../i18n.dart';
import '../services/settings.dart';
import 'chatgpt_auth.dart';
import 'responses_client.dart';

/// 用登录的 ChatGPT 账号调用 AI。
/// 每个任务：准备提示词和格式 → 调用 → 校验，不合格就带着问题让 GPT 改，最多重试 2 次。
class DirectAi implements AiService {
  DirectAi({required this.kb, ChatGptAuth? auth, ResponsesClient? client})
      : auth = auth ?? ChatGptAuth(),
        _clientOverride = client;

  final Knowledge kb;
  final ChatGptAuth auth;
  final ResponsesClient? _clientOverride;
  late final ResponsesClient _client = _clientOverride ?? ResponsesClient(auth);
  AiTasks? _tasks;
  // 只记手动选过的模型；没选过就用默认的快模型
  static const _modelKey = 'chatgpt.model.chosen';
  static const _oldModelKey = 'chatgpt.model';

  @override
  String get label => tr('你的 ChatGPT', 'Your ChatGPT', 'Tu ChatGPT');

  /// 用哪个模型：设置里选过就用选的；否则用默认的快模型，账号里没有就用推荐顺序的第一个
  Future<String> model() async {
    final p = await SharedPreferences.getInstance();
    if (p.containsKey(_oldModelKey)) await p.remove(_oldModelKey); // 以前自动记下的模型不算手动选择
    final saved = p.getString(_modelKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final models = _models ??= await _client.listModels();
    if (models.isEmpty) throw AiException('no_model', tr('這個 ChatGPT 帳號沒有可用的模型。', 'This ChatGPT account has no usable models.', 'Esta cuenta de ChatGPT no tiene modelos disponibles.'));
    return models.contains(ResponsesClient.preferredModel) ? ResponsesClient.preferredModel : models.first;
  }

  List<String>? _models;

  static Future<void> setModel(String id) async => (await SharedPreferences.getInstance()).setString(_modelKey, id);
  Future<List<String>> listModels() => _client.listModels();

  @override
  Future<Map<String, dynamic>> task(String name, Map<String, dynamic> params, {bool demo = false, CancelToken? token}) async {
    if (demo) return DemoAi.run(name, params);
    final tasks = _tasks ??= await AiTasks.load(kb);
    final prepared = tasks.prepare(name, {'lang': aiLang, 'student': (await AppSettings.load()).studentName, ...params});
    final m = await model();
    var last = '';
    var issues = <String>[];
    for (var attempt = 1; attempt <= 3; attempt++) {
      final input = attempt == 1 ? prepared.input : [...prepared.input, AiTasks.fixRequest(issues, last)];
      last = (await _call(name, m, () => _client.respond(
        model: m,
        instructions: prepared.instructions,
        input: input,
        schemaName: name,
        schema: prepared.schema,
        token: token,
      ))).text;
      Map<String, dynamic> data;
      try {
        data = jsonDecode(last) as Map<String, dynamic>;
      } catch (_) {
        issues = ['输出不是合法的 JSON'];
        continue;
      }
      issues = prepared.validate(data);
      if (issues.isEmpty) return data;
    }
    throw AiException('invalid_output', '${tr('AI 的回答連續 3 次不符合要求，請重試。', "The AI answer didn't meet the requirements 3 times in a row. Please try again.", 'La respuesta de la IA no cumplió los requisitos 3 veces seguidas. Inténtalo de nuevo.')}（${issues.join('；')}）');
  }
}

extension on DirectAi {
  /// 调用一次并记账（额度监控用）；额度用完时告诉 Benny 最晚什么时候恢复
  Future<AiReply> _call(String task, String model, Future<AiReply> Function() run) async {
    final t0 = DateTime.now();
    try {
      final r = await run();
      await AiUsage.record(AiCall(
        at: t0.millisecondsSinceEpoch, task: task, model: model, ok: true, input: r.input, output: r.output,
        ms: DateTime.now().difference(t0).inMilliseconds,
      ));
      return r;
    } on AiException catch (e) {
      if (e.code == 'cancelled') rethrow;
      await AiUsage.record(AiCall(
        at: t0.millisecondsSinceEpoch, task: task, model: model, ok: false, code: e.code,
        ms: DateTime.now().difference(t0).inMilliseconds,
      ));
      if (e.code == 'quota') throw AiException('quota', quotaMessage((await AiUsage.load()).recoverBy));
      rethrow;
    }
  }
}

/// 检查额度：发一个极小的请求（花一点点额度），看现在能不能用
Future<bool> checkQuota(DirectAi ai) async {
  final m = await ai.model();
  try {
    await ai._call('check', m, () => ai._client.respond(
      model: m,
      instructions: '这是检查连接的请求，ok 填 true。',
      input: [
        {'role': 'user', 'content': [{'type': 'input_text', 'text': 'ok'}]},
      ],
      schemaName: 'check',
      schema: {'type': 'object', 'additionalProperties': false, 'required': ['ok'], 'properties': {'ok': {'type': 'boolean'}}},
    ));
    return true;
  } on AiException catch (e) {
    if (e.code == 'quota') return false;
    rethrow;
  }
}

/// 示例模式：不连 AI，用 assets/demo.json 里的固定数据
abstract final class DemoAi {
  static Map<String, dynamic>? _demo;

  static Future<Map<String, dynamic>> run(String name, Map<String, dynamic> params) async {
    final all = _demo ??= jsonDecode(await rootBundle.loadString('assets/demo.json')) as Map<String, dynamic>;
    // 用界面语言的那一版示例（en / es / zh 繁体）
    final demo = (all[i18n.lang.name] as Map?)?.cast<String, dynamic>() ?? (all['en'] as Map).cast<String, dynamic>();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    Map<String, dynamic> copy(Object? o) => jsonDecode(jsonEncode(o)) as Map<String, dynamic>;
    return switch (name) {
      'analyze' => copy(demo['analysis']),
      'training' => copy(demo['training']),
      'recheck' => {
          'verdict': '全对', 'unreadable_reason': null, 'final_answer_seen': '${(demo['analysis']['accepted_answers'] as List).first}',
          'first_error_step': null, 'error_type': '无错误',
          'comment': demo['gradeComment'] ?? '',
        },
      'steps' => copy(demo['steps']),
      // 示例：第 2 步判错（看看"错了怎么办"），其他步判对
      'stepcheck' => () {
          final k = params['step'] as int? ?? 1;
          final st = ((demo['steps'] as Map)['steps'] as List)[(k - 1).clamp(0, 99)] as Map;
          final wrong = demo['stepWrong'] as Map;
          return k == 2
              ? {'verdict': '错', 'seen': wrong['seen'], 'where': wrong['where'], 'comment': wrong['comment']}
              : {'verdict': '对', 'seen': '${st['result']}'.replaceAll(r'$', ''), 'where': '', 'comment': demo['stepRight']};
        }(),
      _ => throw AiException('bad_task', '没有这个任务：$name'),
    };
  }
}
