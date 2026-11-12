import 'dart:async';
import 'dart:io';

import '../i18n.dart';

/// 在 127.0.0.1 的随机端口上接收登录回调（OpenAI 只允许回调到本机地址，端口可以变）
class LoopbackServer {
  LoopbackServer._(this._server);

  final HttpServer _server;

  static Future<LoopbackServer> start() async => LoopbackServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  int get port => _server.port;

  /// 等到第一个访问 [path] 的请求，返回它的查询参数；同时给浏览器回一个"可以关掉了"的页面
  Future<Map<String, String>> waitForCallback(String path, {required Duration timeout}) async {
    await for (final req in _server.timeout(timeout, onTimeout: (sink) => sink.close())) {
      if (req.uri.path != path) {
        req.response
          ..statusCode = HttpStatus.notFound
          ..close();
        continue;
      }
      final ok = req.uri.queryParameters['error'] == null;
      req.response
        ..headers.contentType = ContentType.html
        ..write('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<body style="font:20px -apple-system,sans-serif;text-align:center;padding-top:30vh">'
            '${ok ? tr('登入完成，正在回到 Benny Math…', "Signed in! Going back to Benny Math…", '¡Sesión iniciada! Volviendo a Benny Math…') : tr('登入沒有完成，請回到 App 再試一次。', 'Sign-in was not completed. Go back to the app and try again.', 'No se completó el inicio de sesión. Vuelve a la app e inténtalo de nuevo.')}</body>');
      await req.response.close();
      return req.uri.queryParameters;
    }
    throw TimeoutException('登录超时');
  }

  Future<void> close() => _server.close(force: true);
}
