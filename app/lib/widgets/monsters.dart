import 'package:flutter/material.dart';

import '../i18n.dart';
import 'sprite.dart';

/// 练习小怪（32×32 像素画），按难度分。错题怪兽是现场生成的，见 game/monster_art.dart。
class MonsterInfo {
  const MonsterInfo(this.name, this.sprite, {this.title = ''});
  final String name;
  final String title;
  final String sprite;
}

/// 练习难度 → 小怪
MonsterInfo practiceMonster(String level) => switch (level) {
      '基础' => MonsterInfo(tr('史萊姆', 'Slime', 'Limo'), 'monster_slime'),
      '变式' => MonsterInfo(tr('骷髏兵', 'Skeleton', 'Esqueleto'), 'monster_skeleton'),
      '挑战' => MonsterInfo(tr('小 Boss', 'Mini Boss', 'Minijefe'), 'monster_boss'),
      _ => MonsterInfo(tr('騎士', 'Knight', 'Caballero'), 'monster_knight'),
    };

/// 画怪兽；defeated 时变灰、倒下
class MonsterSprite extends StatelessWidget {
  const MonsterSprite(this.monster, {super.key, this.size = 96, this.defeated = false});

  final MonsterInfo monster;
  final double size;
  final bool defeated;

  @override
  Widget build(BuildContext context) => Semantics(
        label: monster.name,
        image: true,
        child: AnimatedRotation(
          turns: defeated ? 0.25 : 0,
          duration: const Duration(milliseconds: 400),
          child: Sprite(monster.sprite, width: size, height: size, color: defeated ? greyscale : null),
        ),
      );
}
