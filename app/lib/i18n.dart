import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 界面语言：英语（默认）、西班牙语、繁体中文。不支持简体中文。
/// 第一次打开跟着设备的语言走，之后在设置里改。
/// 用法：tr('繁體中文', 'English', 'Español')——三种文字写在一起，改的时候一眼能看到对应关系。
/// 存档、知识点编号、错因这些内部的值还是简体中文，只在显示时翻译。
enum Lang {
  en('English'),
  es('Español'),
  zh('繁體中文'); // 繁体中文（存的值还叫 zh，和以前的中文设置兼容）

  const Lang(this.label);
  final String label;

  static Lang parse(String? s) => switch (s) { 'zh' => Lang.zh, 'es' => Lang.es, 'en' => Lang.en, _ => fromLocale(PlatformDispatcher.instance.locale) };

  /// 设备语言是西班牙语就用西班牙语，中文（简体、繁体都算）就用繁体中文，其余用英语
  static Lang fromLocale(Locale l) => switch (l.languageCode) { 'es' => Lang.es, 'zh' => Lang.zh, _ => Lang.en };
}

class I18n extends ChangeNotifier {
  Lang _lang = Lang.en;
  Lang get lang => _lang;
  bool get zh => _lang == Lang.zh;
  bool get es => _lang == Lang.es;

  static const _key = 'app.lang';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _lang = Lang.parse(p.getString(_key));
    notifyListeners();
  }

  Future<void> set(Lang l) async {
    if (l == _lang) return;
    _lang = l;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_key, l.name);
  }

  /// 测试用
  @visibleForTesting
  void setForTest(Lang l) => _lang = l;
}

final i18n = I18n();

String tr(String zh, String en, String es) => switch (i18n.lang) { Lang.zh => zh, Lang.es => es, Lang.en => en };

/// AI 生成内容用的语言代码（发给 GPT）：en / es / zh（繁体）
String get aiLang => i18n.lang.name;
