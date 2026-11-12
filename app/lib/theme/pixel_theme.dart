import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../i18n.dart';

/// 调色板：暖色纸面 + 深蓝紫描边。整个 App 只用这里的颜色，不用渐变和模糊。
abstract final class Px {
  static const ink = Color(0xff23243a); // 描边、正文
  static const paper = Color(0xfff6f1e4); // 背景
  static const paperDim = Color(0xffeae3d2); // 凹进去的底色
  static const panel = Color(0xfffffdf7); // 面板
  static const sky = Color(0xff3b7dd8); // 主色
  static const skyLight = Color(0xffdbe8fb);
  static const grass = Color(0xff4fa84a); // 成功
  static const grassLight = Color(0xffe1f2d6);
  static const sun = Color(0xfff2c14e); // 提醒
  static const sunLight = Color(0xfffff3cc);
  static const amber = Color(0xffb86e00); // 提醒的文字
  static const brick = Color(0xffd9534f); // 错误
  static const brickLight = Color(0xfffbe1dc);
  static const stone = Color(0xffa3adb8); // 未检测、次要
  static const shadow = Color(0xff646a7a); // 次要文字
  static const okText = Color(0xff2f7a2c);
}

/// 知识点掌握状态 → 颜色和名字（规则在 logic/mastery.dart，没有记录的是 untested）
enum KpStatus {
  solid('熟練', 'Mastered', 'Dominado', Px.grass),
  basic('基本掌握', 'Got it', 'Lo tiene', Px.sky),
  learning('學習中', 'Learning', 'Aprendiendo', Px.sun),
  weak('薄弱', 'Weak', 'Débil', Px.brick),
  untested('未檢測', 'Untested', 'Sin evaluar', Px.stone);

  const KpStatus(this._zh, this._en, this._es, this.color);
  final String _zh;
  final String _en;
  final String _es;
  final Color color;
  String get label => tr(_zh, _en, _es);

  static KpStatus parse(String? s) =>
      KpStatus.values.firstWhere((v) => v.name == s, orElse: () => KpStatus.untested);
}

/// 中文像素字体（缝合像素字体）。字体文件没打包时自动退回系统字体。
const pixelFontFamily = 'FusionPixel';
const _fallback = ['PingFang TC', 'PingFang SC', 'Heiti TC', 'Noto Sans TC', 'sans-serif'];

TextStyle pixelText(double size, {Color color = Px.ink, FontWeight weight = FontWeight.w400}) => TextStyle(
      fontFamily: pixelFontFamily,
      fontFamilyFallback: _fallback,
      fontSize: size,
      height: 1.5,
      color: color,
      fontWeight: weight,
    );

/// 像素粗细：边框、按钮都是 2 像素（原来 4 像素太粗）
const pixelUnit = 2;

ThemeData buildPixelTheme() {
  final textTheme = TextTheme(
    displaySmall: pixelText(36),
    headlineMedium: pixelText(28),
    headlineSmall: pixelText(24),
    titleLarge: pixelText(22),
    titleMedium: pixelText(18),
    bodyLarge: pixelText(18),
    bodyMedium: pixelText(16),
    bodySmall: pixelText(14),
    labelLarge: pixelText(16),
    labelMedium: pixelText(14),
    labelSmall: pixelText(12),
  );
  return flutterNesTheme(
    primaryColor: Px.sky,
    textTheme: textTheme,
    nesTheme: const NesTheme(pixelSize: pixelUnit),
    nesButtonTheme: const NesButtonTheme(
      normal: Px.panel,
      primary: Px.sky,
      success: Px.grass,
      warning: Px.sun,
      error: Px.brick,
      lightLabelColor: Colors.white,
      darkLabelColor: Px.ink,
      lightIconTheme: NesIconTheme(primary: Colors.white, secondary: Px.ink, accent: Px.stone, shadow: Px.shadow),
      darkIconTheme: NesIconTheme(primary: Px.ink, secondary: Colors.white, accent: Px.shadow, shadow: Px.stone),
    ),
    nesIconTheme: const NesIconTheme(primary: Px.ink, secondary: Colors.white, accent: Px.stone, shadow: Px.shadow),
    nesContainerTheme: NesContainerTheme(backgroundColor: Px.panel, borderColor: Px.ink, labelTextStyle: pixelText(15, weight: FontWeight.w700)),
    nesSnackbarTheme: const NesSnackbarTheme(normal: Px.panel, success: Px.grass, warning: Px.sun, error: Px.brick),
  ).copyWith(scaffoldBackgroundColor: Px.paper);
}

/// 手机这样的窄屏（宽度小于 600）
bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// 页面四周的留白：手机上窄一些
EdgeInsets pagePadding(BuildContext context) =>
    isNarrow(context) ? const EdgeInsets.fromLTRB(14, 10, 14, 40) : const EdgeInsets.fromLTRB(24, 12, 24, 48);
