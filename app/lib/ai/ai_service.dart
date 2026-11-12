import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// AI 任务的统一接口。实现：
/// - DirectAi：用登录的 ChatGPT 账号调用
/// - LocalDemoAi：示例数据，不调用 AI
/// 任务：analyze / training / recheck / steps / stepcheck（提示词、输出格式和校验在 ai_tasks.dart）
abstract class AiService {
  /// 给用户看的来源名
  String get label;

  Future<Map<String, dynamic>> task(String name, Map<String, dynamic> params, {bool demo = false, CancelToken? token});
}

/// 每一步最多拍几张照片（一张纸写不下时接着拍）
const maxPhotos = 6;

/// 照片字节 → data URL（按文件头判断格式）
String imageDataUrl(Uint8List bytes) {
  var mime = 'image/jpeg';
  if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50) mime = 'image/png';
  if (bytes.length > 12 && String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') mime = 'image/webp';
  if (bytes.length > 12 && String.fromCharCodes(bytes.sublist(4, 12)).startsWith('ftyphei')) mime = 'image/heic';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

class AiException implements Exception {
  AiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// 取消一次前台请求：关闭它的 http 连接
class CancelToken {
  final _done = Completer<void>();
  http.Client? _client;
  bool get isCancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;

  /// 把这次请求用的连接交给取消令牌
  void attach(http.Client client) {
    _client = client;
    if (isCancelled) client.close();
  }

  void cancel() {
    if (_done.isCompleted) return;
    _done.complete();
    _client?.close();
  }
}
