import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../i18n.dart';
import 'ai_service.dart';
import 'chatgpt_auth.dart';

/// 一次回答：模型输出的文字（JSON 字符串）和用掉的 token
class AiReply {
  const AiReply(this.text, {this.input = 0, this.output = 0});
  final String text;
  final int input;
  final int output;
}

/// 用 ChatGPT 订阅额度调用 Responses API：
/// store=false、stream=true、每次带完整上下文、用 instructions 不用 system 消息、不传 temperature 等字段。
class ResponsesClient {
  ResponsesClient(this.auth);

  /// 默认模型和思考强度：2026-10 实测 GPT-5.6-Luna 低思考强度数学题全对，生成速度约是 GPT-6-Astra 的两倍
  static const preferredModel = 'gpt-5.6-luna';
  static const reasoningEffort = 'low';

  final ChatGptAuth auth;
  static const _api = 'https://api.openai.com/v1';

  static AiException mapError(String? code, String? message) => switch (code) {
        'subscription_sharing_usage_limit_exceeded' =>
          AiException('quota', tr('ChatGPT 額度暫時用完了（Plus 有 5 小時額度限制，也可能到了你給這個應用設的上限）。過一會兒再試。', 'The ChatGPT quota is used up for now (Plus has a 5-hour limit, or the limit you set for this app was reached). Try again later.', 'La cuota de ChatGPT se ha agotado por ahora (Plus tiene un límite de 5 horas, o se alcanzó el límite que pusiste para esta app). Inténtalo más tarde.')),
        'subscription_sharing_invalid_user' => AiException('not_connected', tr('ChatGPT 帳號連線已失效，請在設定裡重新登入。', 'The ChatGPT connection is no longer valid. Please sign in again in Settings.', 'La conexión con ChatGPT ya no es válida. Vuelve a iniciar sesión en Ajustes.')),
        _ => AiException(code ?? 'ai_error', message ?? tr('AI 請求失敗，請重試。', 'The AI request failed. Please try again.', 'La petición a la IA falló. Inténtalo de nuevo.')),
      };

  /// 可选的模型：visibility 为 list、能看图，按官方推荐顺序排
  Future<List<String>> listModels() async {
    final client = http.Client();
    final String body;
    try {
      final res = await _send(client, () => http.Request('GET', Uri.parse('$_api/models')), null);
      body = await res.stream.bytesToString();
      if (res.statusCode >= 400) throw _httpError(res.statusCode, body);
    } finally {
      client.close();
    }
    final data = jsonDecode(body);
    final all = (data is List ? data : (data['data'] ?? data['models'] ?? [])) as List;
    final usable = all.whereType<Map>().where((m) => m['visibility'] == null || m['visibility'] == 'list').where((m) {
      final mod = m['input_modalities'];
      return mod == null || (mod as List).contains('image');
    }).toList()
      ..sort((a, b) => ((a['priority'] as num?) ?? 999).compareTo((b['priority'] as num?) ?? 999));
    return [for (final m in usable.isEmpty ? all.whereType<Map>() : usable) '${m['id'] ?? m['slug'] ?? m['name']}'];
  }

  /// 发一次请求，返回模型输出的文字（JSON 字符串）和用掉的 token
  Future<AiReply> respond({
    required String model,
    required String instructions,
    required List<Map<String, dynamic>> input,
    required String schemaName,
    required Map<String, dynamic> schema,
    String effort = reasoningEffort,
    CancelToken? token,
  }) async {
    final body = jsonEncode({
      'model': model,
      'reasoning': {'effort': effort},
      'instructions': instructions,
      'input': input,
      'store': false,
      'stream': true,
      'text': {
        'format': {'type': 'json_schema', 'name': schemaName, 'schema': schema, 'strict': true},
      },
    });
    final client = http.Client();
    token?.attach(client);
    try {
      final res = await _send(
        client,
        () => http.Request('POST', Uri.parse('$_api/responses'))
          ..headers['Content-Type'] = 'application/json'
          ..headers['Accept'] = 'text/event-stream'
          ..body = body,
        token,
      );
      if (res.statusCode >= 400) throw _httpError(res.statusCode, await res.stream.bytesToString());
      return await readReply(res.stream.transform(utf8.decoder));
    } on AiException {
      rethrow;
    } catch (e) {
      // 读流时被取消或断网
      if (token?.isCancelled ?? false) throw AiException('cancelled', tr('已取消', 'Cancelled', 'Cancelado'));
      throw AiException('interrupted', tr('AI 的回答中途斷開了（$e），請重試。', 'The AI answer was cut off ($e). Please try again.', 'La respuesta de la IA se cortó ($e). Inténtalo de nuevo.'));
    } finally {
      client.close();
    }
  }

  /// 发请求（连接由调用方负责关闭）；401 时刷新令牌重试一次
  Future<http.StreamedResponse> _send(http.Client client, http.Request Function() build, CancelToken? token, {bool retry = true}) async {
    try {
      final req = build()..headers['Authorization'] = 'Bearer ${await auth.accessToken()}';
      final res = await client.send(req).timeout(const Duration(minutes: 5));
      if (res.statusCode == 401 && retry) {
        await res.stream.drain<void>();
        await auth.accessToken(forceRefresh: true);
        return await _send(client, build, token, retry: false);
      }
      return res;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('timeout', tr('AI 太久沒有回應，請重試。', 'The AI took too long to answer. Please try again.', 'La IA tardó demasiado en responder. Inténtalo de nuevo.'));
    } catch (e) {
      if (token?.isCancelled ?? false) throw AiException('cancelled', tr('已取消', 'Cancelled', 'Cancelado'));
      throw AiException('network', tr('連不上 OpenAI（$e）。請檢查網路。', "Can't reach OpenAI ($e). Please check the internet connection.", 'No se puede conectar con OpenAI ($e). Revisa la conexión a internet.'));
    }
  }

  static AiException _httpError(int status, String body) {
    try {
      final e = (jsonDecode(body) as Map)['error'] as Map?;
      return mapError('${e?['code'] ?? e?['type'] ?? 'http_$status'}', '${e?['message'] ?? 'HTTP $status'}');
    } catch (_) {
      return mapError('http_$status', 'HTTP $status：${body.length > 200 ? body.substring(0, 200) : body}');
    }
  }

  static Future<String> readStream(Stream<String> chunks) async => (await readReply(chunks)).text;

  /// 读事件流：只有收到 response.completed 才算成功；failed / incomplete / 中途断开都按失败处理
  static Future<AiReply> readReply(Stream<String> chunks) async {
    var buf = '';
    final deltas = StringBuffer();
    Map<String, dynamic>? done;
    await for (final chunk in chunks) {
      buf += chunk.replaceAll('\r\n', '\n');
      int cut;
      while ((cut = buf.indexOf('\n\n')) >= 0) {
        final block = buf.substring(0, cut);
        buf = buf.substring(cut + 2);
        final data = block.split('\n').where((l) => l.startsWith('data:')).map((l) => l.substring(5).trimLeft()).join('\n');
        if (data.isEmpty || data == '[DONE]') continue;
        Map<String, dynamic> ev;
        try {
          ev = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        switch (ev['type']) {
          case 'response.output_text.delta':
            deltas.write(ev['delta'] ?? '');
          case 'response.completed':
            done = (ev['response'] as Map).cast<String, dynamic>();
          case 'response.failed':
            final err = ((ev['response'] as Map?)?['error'] as Map?);
            throw mapError(err?['code'] as String?, err?['message'] as String? ?? tr('AI 回答失敗，請重試。', 'The AI could not answer. Please try again.', 'La IA no pudo responder. Inténtalo de nuevo.'));
          case 'response.incomplete':
            final why = (((ev['response'] as Map?)?['incomplete_details']) as Map?)?['reason'];
            throw AiException('incomplete', tr('AI 的回答沒有寫完（${why ?? '原因未知'}），請重試。', 'The AI answer was incomplete (${why ?? 'unknown reason'}). Please try again.', 'La respuesta de la IA estaba incompleta (${why ?? 'motivo desconocido'}). Inténtalo de nuevo.'));
          case 'error':
            throw mapError((ev['code'] ?? (ev['error'] as Map?)?['code']) as String?, (ev['message'] ?? (ev['error'] as Map?)?['message']) as String?);
        }
      }
    }
    final response = done;
    if (response == null) throw AiException('interrupted', tr('AI 的回答中途斷開了，請重試。', 'The AI answer was cut off. Please try again.', 'La respuesta de la IA se cortó. Inténtalo de nuevo.'));
    final parts = [
      for (final o in (response['output'] as List? ?? []).whereType<Map>())
        if (o['type'] == 'message') ...(o['content'] as List? ?? []).whereType<Map>(),
    ];
    final refusal = parts.where((c) => c['type'] == 'refusal');
    if (refusal.isNotEmpty) throw AiException('refusal', '${tr('AI 拒絕回答：', 'The AI declined to answer: ', 'La IA no quiso responder: ')}${refusal.first['refusal'] ?? ''}');
    final text = parts.where((c) => c['type'] == 'output_text').map((c) => '${c['text']}').join();
    final usage = response['usage'] as Map?;
    return AiReply(
      text.isNotEmpty ? text : deltas.toString(),
      input: (usage?['input_tokens'] as num?)?.toInt() ?? 0,
      output: (usage?['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }
}
