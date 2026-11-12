import 'package:flutter/material.dart';

/// 像素画素材（assets/art/，由 tool/art/build.py 生成）。按最近邻放大，像素不会糊。
class Sprite extends StatelessWidget {
  const Sprite(this.name, {super.key, this.width, this.height, this.color, this.semanticLabel});

  final String name;
  final double? width;
  final double? height;
  final ColorFilter? color;
  final String? semanticLabel;

  static String path(String name) => 'assets/art/$name.png';

  /// 先把要切换的帧都解码好，换帧时不会闪
  static Future<void> precache(BuildContext context, Iterable<String> names) =>
      Future.wait([for (final n in names) precacheImage(AssetImage(path(n)), context)]);

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      path(name),
      width: width,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
    return color == null ? img : ColorFiltered(colorFilter: color!, child: img);
  }
}

/// 变灰（被打倒的怪兽、没开放的地方）
const greyscale = ColorFilter.matrix(<double>[
  0.3, 0.5, 0.2, 0, 20, //
  0.3, 0.5, 0.2, 0, 20,
  0.3, 0.5, 0.2, 0, 20,
  0, 0, 0, 0.75, 0,
]);
