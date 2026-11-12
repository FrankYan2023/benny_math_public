import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../i18n.dart';
import 'ai_service.dart';
import 'loopback_server.dart';

/// "用 ChatGPT 账号登录"（OpenAI 给开源、本地运行的应用的订阅额度共享流程）：
/// 文档 https://developers.openai.com/siwc/token-sharing-open-source/sign-in
/// 动态注册 + PKCE，回调到 http://127.0.0.1:<端口>/auth/callback（App 自己在本机监听），
/// 登录页在 App 内的 Safari 页面里打开。凭证存在 iPad 的钥匙串里，不离开这台设备。
class ChatGptAccount {
  ChatGptAccount({required this.name, required this.email});
  final String? name;
  final String? email;
}

class ChatGptAuth {
  ChatGptAuth({FlutterSecureStorage? storage, http.Client? client})
      : _store = storage ?? const FlutterSecureStorage(),
        _http = client ?? http.Client();

  static const issuer = 'https://auth.openai.com';
  static const _authorizeUrl = '$issuer/api/accounts/authorize';
  static const _tokenUrl = '$issuer/api/accounts/oauth/token';
  static const resource = 'https://api.openai.com/v1';
  static const _scope = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';
  static const _agentName = 'Benny Math';
  static const _callbackPath = '/auth/callback';
  static const _credsKey = 'chatgpt.credentials';
  static const _regKey = 'chatgpt.registration'; // ext_agent_host_id、已发放的 client_id、上次的 id_token

  final FlutterSecureStorage _store;
  final http.Client _http;
  Future<String>? _refreshing;

  Future<Map<String, dynamic>> _read(String key) async {
    final s = await _store.read(key: key);
    return s == null ? {} : (jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> _write(String key, Map<String, dynamic> value) => _store.write(key: key, value: jsonEncode(value));

  Future<ChatGptAccount?> account() async {
    final c = await _read(_credsKey);
    return c['accessToken'] == null ? null : ChatGptAccount(name: c['name'] as String?, email: c['email'] as String?);
  }

  static String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static String _random(int n) {
    final r = Random.secure();
    return _b64url(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  /// 打开登录页，等用户登录并授权，换取令牌并保存
  Future<ChatGptAccount> signIn() async {
    final reg = await _read(_regKey);
    reg['hostId'] ??= 'urn:uuid:${const Uuid().v4()}';
    await _write(_regKey, reg);

    final server = await LoopbackServer.start();
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}$_callbackPath';
      final verifier = _random(32);
      final state = _random(16);
      final nonce = _random(16);
      final params = <String, String>{
        'client_id': reg['clientId'] as String? ?? 'dynamic_agent_client',
        'ext_agent_host_id': reg['hostId'] as String,
        'redirect_uri': redirectUri,
        'scope': _scope,
        'response_type': 'code',
        'code_challenge': _b64url(sha256.convert(utf8.encode(verifier)).bytes),
        'code_challenge_method': 'S256',
        'state': state,
        'nonce': nonce,
        'resource': resource,
      };
      // 首次注册时带应用名；之后用已发放的 client_id，并带上次的 id_token 作为提示
      if (reg['clientId'] == null) {
        params['agent_name_hint'] = _agentName;
      } else if (reg['idTokenHint'] != null) {
        params['id_token_hint'] = reg['idTokenHint'] as String;
      }
      final opened = await launchUrl(Uri.parse(_authorizeUrl).replace(queryParameters: params), mode: LaunchMode.inAppBrowserView);
      if (!opened) throw AiException('launch_failed', tr('打不開登入頁面。', "Couldn't open the sign-in page.", 'No se pudo abrir la página de inicio de sesión.'));

      final Map<String, String> q;
      try {
        q = await server.waitForCallback(_callbackPath, timeout: const Duration(minutes: 10));
      } on TimeoutException {
        throw AiException('timeout', tr('登入超過 10 分鐘沒有完成，請重試。', 'Sign-in took more than 10 minutes. Please try again.', 'El inicio de sesión tardó más de 10 minutos. Inténtalo de nuevo.'));
      } finally {
        unawaited(closeInAppWebView().catchError((_) {}));
      }
      if (q['error'] != null) throw AiException('denied', '${tr('登入沒有完成：', 'Sign-in was not completed: ', 'No se completó el inicio de sesión: ')}${q['error_description'] ?? q['error']}');
      if (q['state'] != state) throw AiException('state', tr('登入狀態對不上，請重新登入。', 'Sign-in state did not match. Please sign in again.', 'El estado del inicio de sesión no coincide. Vuelve a iniciar sesión.'));
      final code = q['code'];
      final clientId = q['client_id'] ?? reg['clientId'] as String?;
      if (code == null || clientId == null) throw AiException('no_code', tr('登入回調裡缺少授權資訊，請重新登入。', 'The sign-in reply was missing information. Please sign in again.', 'A la respuesta del inicio de sesión le faltaba información. Vuelve a iniciar sesión.'));

      final tok = await _token({
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
        'resource': resource,
      });
      final claims = _checkIdToken(tok['id_token'] as String?, clientId, nonce);

      reg
        ..['clientId'] = clientId
        ..['idTokenHint'] = tok['id_token'];
      await _write(_regKey, reg);
      await _write(_credsKey, {
        'clientId': clientId,
        'sub': claims['sub'],
        'name': claims['name'],
        'email': claims['email'],
        'accessToken': tok['access_token'],
        'refreshToken': tok['refresh_token'],
        'expiresAt': DateTime.now().add(Duration(seconds: (tok['expires_in'] as num?)?.toInt() ?? 3600)).millisecondsSinceEpoch,
      });
      return ChatGptAccount(name: claims['name'] as String?, email: claims['email'] as String?);
    } finally {
      await server.close();
    }
  }

  Future<Map<String, dynamic>> _token(Map<String, String> fields) async {
    final res = await _http.post(Uri.parse(_tokenUrl), headers: {'Accept': 'application/json'}, body: fields).timeout(const Duration(seconds: 30));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      data = {'error': 'http_${res.statusCode}'};
    }
    if (res.statusCode >= 400 || data['error'] != null) {
      throw AiException('${data['error'] ?? 'http_${res.statusCode}'}', '${data['error_description'] ?? data['error'] ?? tr('登入服務出錯（${res.statusCode}）', 'The sign-in service failed (${res.statusCode})', 'El servicio de inicio de sesión falló (${res.statusCode})')}');
    }
    return data;
  }

  /// id_token 是本 App 通过 TLS 直接从令牌接口拿到的，这里校验声明（签发方、受众、有效期、nonce）
  static Map<String, dynamic> _checkIdToken(String? idToken, String clientId, String nonce) {
    // 下面这些只在登录服务出问题时出现，统一给一句能看懂的提示，原因放在括号里
    String bad(String why) => tr('登入資訊不對（$why），請重新登入。', 'The sign-in reply looks wrong ($why). Please sign in again.', 'La respuesta del inicio de sesión no es correcta ($why). Vuelve a iniciar sesión.');
    if (idToken == null) throw AiException('id_token', bad('no id_token'));
    final parts = idToken.split('.');
    if (parts.length != 3) throw AiException('id_token', bad('id_token format'));
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    final iss = '${claims['iss']}'.replaceAll(RegExp(r'/$'), '');
    final aud = claims['aud'] is List ? (claims['aud'] as List).map((e) => '$e').toList() : ['${claims['aud']}'];
    final exp = (claims['exp'] as num?)?.toInt() ?? 0;
    if (iss != issuer) throw AiException('id_token', bad('issuer'));
    if (!aud.contains(clientId)) throw AiException('id_token', bad('audience'));
    if (exp * 1000 < DateTime.now().millisecondsSinceEpoch - 60000) throw AiException('id_token', bad('expired'));
    if (claims['nonce'] != nonce) throw AiException('id_token', bad('nonce'));
    if (claims['sub'] == null) throw AiException('id_token', bad('no account id'));
    return claims;
  }

  /// 有效的访问令牌；快过期时用 refresh_token 换新的（refresh_token 每次都会轮换）
  Future<String> accessToken({bool forceRefresh = false}) async {
    final c = await _read(_credsKey);
    if (c['accessToken'] == null) throw AiException('not_connected', tr('這臺裝置還沒有登入 ChatGPT。請在設定裡登入。', 'This device is not signed in to ChatGPT. Please sign in in Settings.', 'Este dispositivo no ha iniciado sesión en ChatGPT. Inicia sesión en Ajustes.'));
    final expiresAt = (c['expiresAt'] as num?)?.toInt() ?? 0;
    if (!forceRefresh && expiresAt - DateTime.now().millisecondsSinceEpoch > 120000) return c['accessToken'] as String;
    return _refreshing ??= _refresh(c).whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh(Map<String, dynamic> c) async {
    if (c['refreshToken'] == null) {
      await signOut();
      throw AiException('not_connected', tr('ChatGPT 登入已過期，請在設定裡重新登入。', 'The ChatGPT sign-in has expired. Please sign in again in Settings.', 'La sesión de ChatGPT ha caducado. Vuelve a iniciar sesión en Ajustes.'));
    }
    try {
      final tok = await _token({
        'grant_type': 'refresh_token',
        'client_id': c['clientId'] as String,
        'refresh_token': c['refreshToken'] as String,
        'resource': resource,
      });
      c
        ..['accessToken'] = tok['access_token']
        ..['refreshToken'] = tok['refresh_token'] ?? c['refreshToken']
        ..['expiresAt'] = DateTime.now().add(Duration(seconds: (tok['expires_in'] as num?)?.toInt() ?? 3600)).millisecondsSinceEpoch;
      await _write(_credsKey, c);
      return c['accessToken'] as String;
    } on AiException catch (e) {
      if (e.code == 'invalid_grant') {
        await signOut();
        throw AiException('not_connected', tr('ChatGPT 登入已失效，請在設定裡重新登入。', 'The ChatGPT sign-in is no longer valid. Please sign in again in Settings.', 'La sesión de ChatGPT ya no es válida. Vuelve a iniciar sesión en Ajustes.'));
      }
      rethrow;
    }
  }

  /// 断开：删掉令牌（保留注册信息，下次登录同一个账号不用重新注册）
  Future<void> signOut() => _store.delete(key: _credsKey);

  /// 换账号：连注册信息一起删
  Future<void> forget() async {
    await _store.delete(key: _credsKey);
    await _store.delete(key: _regKey);
  }
}
