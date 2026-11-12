import 'package:shared_preferences/shared_preferences.dart';

/// App 设置：孩子的名字（存在本机）。
class AppSettings {
  AppSettings({this.studentName = 'Benny'});

  String studentName;

  static const _nameKey = 'studentName';
  // 以前连后端用的设置，现在不用了（没传上去的学习事件 pendingEvents 由 LocalDb.ingestLegacyQueue 收进本机再删）
  static const _oldKeys = ['backendUrl', 'appToken', 'gatewayUrl', 'studentId'];

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    for (final k in _oldKeys) {
      if (p.containsKey(k)) await p.remove(k);
    }
    return AppSettings(studentName: p.getString(_nameKey) ?? 'Benny');
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_nameKey, studentName.trim().isEmpty ? 'Benny' : studentName.trim());
  }
}
