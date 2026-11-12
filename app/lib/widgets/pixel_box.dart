import 'package:flutter/material.dart';

import '../theme/pixel_theme.dart';

/// 细像素框：2 像素描边、切角，左上一道高光，右下一块像素投影（可关掉），也可以画成虚线框。
/// 投影画在框自己的范围里（右边和下面留出 4 像素），不会压到旁边的东西。
class PixelBox extends StatelessWidget {
  const PixelBox({
    super.key,
    this.child,
    this.width,
    this.height,
    this.color = Px.panel,
    this.border = Px.ink,
    this.shadow = true,
    this.dashed = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget? child;
  final double? width;
  final double? height;
  final Color color;
  final Color border;
  final bool shadow;
  final bool dashed;
  final EdgeInsets padding;

  static const unit = pixelUnit * 1.0;
  static const drop = unit * 2;

  @override
  Widget build(BuildContext context) {
    final extra = shadow ? drop : 0.0;
    return CustomPaint(
      painter: _PixelBoxPainter(color: color, border: border, shadow: shadow, dashed: dashed),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: EdgeInsets.fromLTRB(unit + padding.left, unit + padding.top, unit + extra + padding.right, unit + extra + padding.bottom),
          child: child,
        ),
      ),
    );
  }
}

class _PixelBoxPainter extends CustomPainter {
  _PixelBoxPainter({required this.color, required this.border, required this.shadow, required this.dashed});
  final Color color;
  final Color border;
  final bool shadow;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    const u = PixelBox.unit;
    final s = shadow ? PixelBox.drop : 0.0;
    final w = size.width - s;
    final h = size.height - s;
    if (w <= u * 3 || h <= u * 3) return;

    // 切角的矩形：去掉四个角上的一个像素
    Path notched(double dx, double dy) => Path()
      ..addRect(Rect.fromLTWH(dx + u, dy, w - 2 * u, h))
      ..addRect(Rect.fromLTWH(dx, dy + u, w, h - 2 * u));

    if (shadow) canvas.drawPath(notched(s, s), Paint()..color = Px.ink.withValues(alpha: 0.16));
    canvas.drawPath(notched(0, 0), Paint()..color = color);

    // 左上高光
    final light = Paint()..color = Colors.white.withValues(alpha: color.computeLuminance() > 0.6 ? 0.7 : 0.25);
    canvas.drawRect(Rect.fromLTWH(u * 2, u, w - u * 4, u), light);
    canvas.drawRect(Rect.fromLTWH(u, u * 2, u, h - u * 4), light);

    final line = Paint()..color = border;
    if (!dashed) {
      canvas.drawRect(Rect.fromLTWH(u, 0, w - 2 * u, u), line);
      canvas.drawRect(Rect.fromLTWH(u, h - u, w - 2 * u, u), line);
      canvas.drawRect(Rect.fromLTWH(0, u, u, h - 2 * u), line);
      canvas.drawRect(Rect.fromLTWH(w - u, u, u, h - 2 * u), line);
      return;
    }
    // 虚线：每段 3 像素长，空 2 像素
    const dash = u * 3, gapLen = u * 2;
    for (var x = u; x < w - u; x += dash + gapLen) {
      final len = (x + dash > w - u) ? w - u - x : dash;
      canvas.drawRect(Rect.fromLTWH(x, 0, len, u), line);
      canvas.drawRect(Rect.fromLTWH(x, h - u, len, u), line);
    }
    for (var y = u; y < h - u; y += dash + gapLen) {
      final len = (y + dash > h - u) ? h - u - y : dash;
      canvas.drawRect(Rect.fromLTWH(0, y, u, len), line);
      canvas.drawRect(Rect.fromLTWH(w - u, y, u, len), line);
    }
  }

  @override
  bool shouldRepaint(_PixelBoxPainter old) => old.color != color || old.border != border || old.shadow != shadow || old.dashed != dashed;
}
