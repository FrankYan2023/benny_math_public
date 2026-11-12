import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import 'sprite.dart';

/// 小加和小减：Benny 的两只小乌龟——小加（大的，绿壳）和小减（小的，红壳），一起当向导。44×32 像素画，表情各一张图。
/// 会轻轻跳动，平时偶尔眨眼。size 是高度。
enum TurtleMood { idle, happy, oops, thinking }

class Turtles extends StatefulWidget {
  const Turtles({super.key, this.size = 128, this.mood = TurtleMood.idle});

  final double size;
  final TurtleMood mood;

  static const frames = ['pet_idle', 'pet_blink', 'pet_happy', 'pet_oops', 'pet_thinking'];

  @override
  State<Turtles> createState() => _TurtlesState();
}

class _TurtlesState extends State<Turtles> {
  Timer? _timer;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 450), (_) => setState(() => _frame++));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final blink = !still && widget.mood == TurtleMood.idle && _frame % 9 == 0;
    final px = widget.size / 32;
    final bounce = still || _frame.isEven ? 0.0 : -px;
    return Semantics(
      label: tr('小加和小減（兩隻小烏龜）', 'Plus and Minus (two little turtles)', 'Más y Menos (dos tortuguitas)'),
      image: true,
      child: SizedBox(
        width: widget.size * 44 / 32,
        height: widget.size,
        child: Transform.translate(
          offset: Offset(0, bounce),
          child: Sprite(blink ? 'pet_blink' : 'pet_${widget.mood.name}', width: widget.size * 44 / 32, height: widget.size),
        ),
      ),
    );
  }
}
