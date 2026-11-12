import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import 'sprite.dart';

/// Benny：胖胖的、戴黑框眼镜、板刷头的中国男孩，黑色连帽衫带青色亮边（32×36 像素画）。
class Benny extends StatefulWidget {
  const Benny({super.key, this.height = 144, this.happy = false});

  final double height;
  final bool happy;

  static const frames = ['benny_idle', 'benny_happy', 'benny_blink', 'benny_walk_0', 'benny_walk_1'];

  @override
  State<Benny> createState() => _BennyState();
}

class _BennyState extends State<Benny> {
  Timer? _timer;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() => _frame++));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final width = widget.height * 32 / 36;
    final px = widget.height / 36;
    final blink = !still && !widget.happy && _frame % 7 == 3;
    return Semantics(
      label: 'Benny',
      image: true,
      child: SizedBox(
        width: width,
        height: widget.height,
        child: Transform.translate(
          offset: Offset(0, still || _frame.isEven ? 0 : -px),
          child: Sprite(blink ? 'benny_blink' : (widget.happy ? 'benny_happy' : 'benny_idle'), width: width, height: widget.height),
        ),
      ),
    );
  }
}

/// 地图上走路的小 Benny（16×20，两帧）
class BennyWalker extends StatefulWidget {
  const BennyWalker({super.key, required this.scale});
  final double scale;

  @override
  State<BennyWalker> createState() => _BennyWalkerState();
}

class _BennyWalkerState extends State<BennyWalker> {
  Timer? _timer;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 420), (_) => setState(() => _frame++));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Sprite('benny_walk_${still ? 0 : _frame % 2}', width: 16 * widget.scale, height: 20 * widget.scale, semanticLabel: tr('Benny 在這裡', 'Benny is here', 'Aquí está Benny'));
  }
}
