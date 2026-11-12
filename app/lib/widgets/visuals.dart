import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../i18n.dart';
import '../theme/pixel_theme.dart';
import 'pixel_box.dart';
import 'math_text.dart';

/// 讲解卡里的动画图示。GPT 只给数据（格式见 ai_tasks.dart 里训练任务的 visual），这里画出来并一帧一帧播放。
/// 支持：数轴 number_line、算式变形 expr_steps、天平 balance、线段图 bar_model。
class LessonVisual extends StatefulWidget {
  const LessonVisual(this.data, {super.key});

  final Map<String, dynamic> data;

  @override
  State<LessonVisual> createState() => _LessonVisualState();
}

class _LessonVisualState extends State<LessonVisual> with SingleTickerProviderStateMixin {
  static const _frameMs = 1200;
  late final AnimationController _c;

  int get _frames => switch (widget.data['kind']) {
        'number_line' => 1 + (widget.data['jumps'] as List).length + (widget.data['spans'] as List).length,
        'expr_steps' || 'balance' => (widget.data['steps'] as List).length,
        'bar_model' => (widget.data['bars'] as List).length,
        _ => 1,
      };

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: _frames * _frameMs));
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  void _play() {
    if (!mounted) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.data;
    return PixelBox(
      color: Px.paper,
      shadow: false,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: MathText('${v['title'] ?? ''}', style: pixelText(16, weight: FontWeight.w700))),
            NesButton(type: NesButtonType.normal, onPressed: _play, child: Text(tr('重播', 'Replay', 'Repetir'), style: pixelText(14))),
          ]),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final pos = _c.value * _frames;
              final frame = _c.isCompleted ? _frames : pos.floor();
              final t = _c.isCompleted ? 1.0 : pos - pos.floor();
              return switch (v['kind']) {
                'number_line' => _NumberLine(v, frame, t),
                'expr_steps' => _ExprSteps(v, frame),
                'balance' => _Balance(v, frame),
                'bar_model' => _BarModel(v, frame, t),
                _ => const SizedBox.shrink(),
              };
            },
          ),
          if ('${v['caption'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            MathText('${v['caption']}', style: pixelText(15, color: Px.shadow)),
          ],
        ],
      ),
    );
  }
}

/// 第 [k] 帧及以后才显示
Widget _reveal(bool on, Widget child) => AnimatedOpacity(
      opacity: on ? 1 : 0,
      duration: const Duration(milliseconds: 350),
      child: AnimatedSlide(offset: on ? Offset.zero : const Offset(0, 0.15), duration: const Duration(milliseconds: 350), child: child),
    );

String _plain(Object? s) => '$s'
    .replaceAll(r'$', '')
    .replaceAllMapped(RegExp(r'\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}'), (m) => '${m[1]}/${m[2]}')
    .replaceAll(RegExp(r'\\[a-zA-Z]+'), '')
    .replaceAll(RegExp(r'[{}\\]'), '')
    .replaceAll('-', '−');

String _num(num x) {
  final s = (x * 10000).round() / 10000;
  final t = s == s.roundToDouble() ? s.toInt().toString() : s.toString();
  return t.replaceAll('-', '−');
}

// ---------- 数轴 ----------
class _NumberLine extends StatelessWidget {
  const _NumberLine(this.v, this.frame, this.t);
  final Map<String, dynamic> v;
  final int frame;
  final double t;

  @override
  Widget build(BuildContext context) {
    final jumps = (v['jumps'] as List).length;
    final spans = (v['spans'] as List).length;
    final lift = jumps == 0 ? 30.0 : 64.0 + math.min(4, jumps) * 14;
    final height = lift + 30 + 70 + (spans > 0 ? 40 : 0);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _NumberLinePainter(v, frame, t, lift + 30)),
    );
  }
}

class _NumberLinePainter extends CustomPainter {
  _NumberLinePainter(this.v, this.frame, this.t, this.axisY);
  final Map<String, dynamic> v;
  final int frame;
  final double t;
  final double axisY;

  void _text(Canvas c, String s, Offset center, {double size = 14, Color color = Px.ink, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: pixelText(size, color: color, weight: bold ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final min = (v['min'] as num).toDouble();
    final max = (v['max'] as num).toDouble();
    final step = ((v['step'] as num?) ?? 1).toDouble();
    if (max <= min || step <= 0) return;
    const pad = 30.0;
    double x(num value) => pad + (value - min) / (max - min) * (size.width - 2 * pad);
    final ink = Paint()
      ..color = Px.shadow
      ..strokeWidth = 2;

    canvas.drawLine(Offset(pad - 16, axisY), Offset(size.width - pad + 16, axisY), ink);
    canvas.drawPath(
      Path()
        ..moveTo(size.width - pad + 18, axisY)
        ..lineTo(size.width - pad + 8, axisY - 6)
        ..lineTo(size.width - pad + 8, axisY + 6)
        ..close(),
      Paint()..color = Px.shadow,
    );
    final count = ((max - min) / step).round();
    final every = count > 20 ? 2 : 1;
    for (var i = 0; i <= count; i++) {
      final tv = min + i * step;
      canvas.drawLine(Offset(x(tv), axisY - 6), Offset(x(tv), axisY + 6), ink);
      if (i % every == 0) _text(canvas, _num(tv), Offset(x(tv), axisY + 22), size: 13, color: tv.abs() < 1e-9 ? Px.ink : Px.shadow, bold: tv.abs() < 1e-9);
    }

    // 第 1 帧之后：移动箭头（逐个画出来）
    final jumps = (v['jumps'] as List).cast<Map>();
    for (var k = 0; k < jumps.length; k++) {
      final f = k + 1;
      if (frame < f) break;
      final progress = frame > f ? 1.0 : t;
      final x1 = x(jumps[k]['from'] as num), x2 = x(jumps[k]['to'] as num);
      final h = 34.0 + k * 14;
      final path = Path()
        ..moveTo(x1, axisY - 9)
        ..quadraticBezierTo((x1 + x2) / 2, axisY - 9 - h * 2, x2, axisY - 9);
      final metric = path.computeMetrics().first;
      final part = metric.extractPath(0, metric.length * progress);
      canvas.drawPath(
        part,
        Paint()
          ..color = Px.sky
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      if (progress >= 1) {
        final tan = metric.getTangentForOffset(metric.length)!;
        final dir = tan.vector / tan.vector.distance;
        final tip = tan.position;
        final normal = Offset(-dir.dy, dir.dx);
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(tip.dx - dir.dx * 12 + normal.dx * 6, tip.dy - dir.dy * 12 + normal.dy * 6)
            ..lineTo(tip.dx - dir.dx * 12 - normal.dx * 6, tip.dy - dir.dy * 12 - normal.dy * 6)
            ..close(),
          Paint()..color = Px.sky,
        );
      }
      if (progress > 0.3) _text(canvas, _plain(jumps[k]['label']), Offset((x1 + x2) / 2, axisY - 18 - h), color: Px.sky, bold: true);
    }

    // 第 0 帧：标点
    for (final p in (v['points'] as List).cast<Map>()) {
      final hl = p['highlight'] == true;
      final c = Offset(x(p['value'] as num), axisY);
      canvas.drawCircle(c, 7, Paint()..color = hl ? Px.brick : Px.paper);
      canvas.drawCircle(c, 7, Paint()
        ..color = hl ? Px.brick : Px.sky
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3);
      _text(canvas, _plain(p['label']), Offset(c.dx, axisY + 46), color: hl ? Px.brick : Px.sky, bold: true);
    }

    // 最后：标出距离
    final spans = (v['spans'] as List).cast<Map>();
    for (var k = 0; k < spans.length; k++) {
      if (frame < jumps.length + 1 + k) break;
      final a = x(math.min(spans[k]['from'] as num, spans[k]['to'] as num));
      final b = x(math.max(spans[k]['from'] as num, spans[k]['to'] as num));
      final y = axisY + 74 + (k % 2) * 4;
      canvas.drawPath(
        Path()
          ..moveTo(a, y - 8)
          ..lineTo(a, y)
          ..lineTo(b, y)
          ..lineTo(b, y - 8),
        Paint()
          ..color = Px.amber
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
      _text(canvas, _plain(spans[k]['label']), Offset((a + b) / 2, y + 16), color: Px.amber, bold: true);
    }
  }

  @override
  bool shouldRepaint(_NumberLinePainter old) => old.frame != frame || old.t != t || old.v != v;
}

// ---------- 算式变形 ----------
class _ExprSteps extends StatelessWidget {
  const _ExprSteps(this.v, this.frame);
  final Map<String, dynamic> v;
  final int frame;

  @override
  Widget build(BuildContext context) {
    final steps = (v['steps'] as List).cast<Map>();
    return Column(
      children: [
        for (var k = 0; k < steps.length; k++)
          _reveal(
            frame >= k,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                if (k > 0) NesIcon(iconData: NesIcons.fatArrowDown, size: const Size.square(16), primaryColor: Px.shadow),
                MathText('\$\$${'${steps[k]['latex']}'.replaceAll(r'$', '')}\$\$', style: pixelText(20)),
                if ('${steps[k]['note'] ?? ''}'.isNotEmpty) MathText('${steps[k]['note']}', style: pixelText(14, color: Px.shadow)),
              ]),
            ),
          ),
      ],
    );
  }
}

// ---------- 天平 ----------
class _Balance extends StatelessWidget {
  const _Balance(this.v, this.frame);
  final Map<String, dynamic> v;
  final int frame;

  @override
  Widget build(BuildContext context) {
    final steps = (v['steps'] as List).cast<Map>();
    Widget pan(Object? tex) => Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Px.ink, width: 4))),
          alignment: Alignment.center,
          child: MathText('\$${'$tex'.replaceAll(r'$', '')}\$', style: pixelText(20)),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          children: [
            for (var k = 0; k < steps.length; k++)
              _reveal(
                frame >= k,
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(children: [
                    if ('${steps[k]['op'] ?? ''}'.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        color: const Color(0xfffff1c2),
                        child: Text('${steps[k]['op']}', style: pixelText(14, color: const Color(0xff8a5a00))),
                      ),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(child: pan(steps[k]['left'])),
                      SizedBox(
                        width: 56,
                        height: 40,
                        child: CustomPaint(painter: _FulcrumPainter()),
                      ),
                      Expanded(child: pan(steps[k]['right'])),
                    ]),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FulcrumPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Px.ink;
    canvas.drawRect(Rect.fromLTWH(0, size.height - 4, size.width, 4), p);
    canvas.drawPath(
      Path()
        ..moveTo(size.width / 2, size.height - 4)
        ..lineTo(size.width / 2 - 12, size.height + 16)
        ..lineTo(size.width / 2 + 12, size.height + 16)
        ..close(),
      p,
    );
    final tp = TextPainter(text: TextSpan(text: '=', style: pixelText(20, color: Px.sky, weight: FontWeight.w700)), textDirection: ui.TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------- 线段图 ----------
class _BarModel extends StatelessWidget {
  const _BarModel(this.v, this.frame, this.t);
  final Map<String, dynamic> v;
  final int frame;
  final double t;

  @override
  Widget build(BuildContext context) {
    final bars = (v['bars'] as List).cast<Map>();
    double total(Map b) => (b['segments'] as List).fold(0.0, (s, x) => s + ((x as Map)['value'] as num).toDouble());
    final maxTotal = bars.map(total).fold(0.0, math.max);
    const colors = [Px.sky, Color(0xff1c5cab), Color(0xff5598e7)];
    return Column(
      children: [
        for (var k = 0; k < bars.length; k++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(width: 72, child: Text('${bars[k]['label']}', textAlign: TextAlign.right, style: pixelText(15, weight: FontWeight.w700))),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final grow = frame > k ? 1.0 : frame == k ? Curves.easeOut.transform(t) : 0.0;
                  final width = c.maxWidth * (maxTotal == 0 ? 0 : total(bars[k]) / maxTotal) * grow;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: width,
                      height: 34,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          maxWidth: c.maxWidth * (maxTotal == 0 ? 0 : total(bars[k]) / maxTotal),
                          child: Row(children: [
                            for (final (j, s) in (bars[k]['segments'] as List).cast<Map>().indexed)
                              Expanded(
                                flex: (((s['value'] as num).toDouble()) * 100).round().clamp(1, 1 << 30),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 2),
                                  color: colors[j % colors.length],
                                  alignment: Alignment.center,
                                  child: Text(_plain(s['label']), maxLines: 1, overflow: TextOverflow.clip, style: pixelText(13, color: Colors.white)),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(width: 10),
              Text('${bars[k]['total_label'] ?? ''}', style: pixelText(14, color: Px.shadow)),
            ]),
          ),
      ],
    );
  }
}
