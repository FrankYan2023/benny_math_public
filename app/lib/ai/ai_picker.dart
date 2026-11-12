import '../i18n.dart';
import '../models/knowledge.dart';
import 'ai_service.dart';
import 'chatgpt_auth.dart';
import 'direct_ai.dart';

/// 示例题：用本地固定数据，不需要 AI
class LocalDemoAi implements AiService {
  @override
  String get label => tr('示例資料', 'Demo data', 'Datos de ejemplo');

  @override
  Future<Map<String, dynamic>> task(String name, Map<String, dynamic> params, {bool demo = false, CancelToken? token}) =>
      DemoAi.run(name, params);
}

/// 选 AI 来源：用登录的 ChatGPT 账号；还没登录返回 null
Future<AiService?> pickAi(Knowledge kb) async {
  try {
    if (await ChatGptAuth().account() != null) return DirectAi(kb: kb);
  } catch (_) {
    // 钥匙串读不了，当作没登录
  }
  return null;
}
