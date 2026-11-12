import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme/pixel_theme.dart';
import '../widgets/benny.dart';
import '../widgets/math_text.dart';
import '../widgets/pixel_box.dart';
import '../widgets/sprite.dart';
import 'game_data.dart';
import 'player.dart';
import 'treasure.dart';
import 'treasure_art.dart';

/// 加了哪些能力：+2 计算力 · +2 逻辑力
String boostText(Treasure t) => [for (final e in t.stats.entries) '+${e.value} ${GameData.instance.statName(e.key)}'].join(' · ');

/// 一件宝藏的卡片：图标、名字、稀有度、来历、加的能力、金币
class TreasureCard extends StatelessWidget {
  const TreasureCard(this.t, {super.key, this.compact = false});
  final Treasure t;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = rarityColors[t.rarity]!;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TreasureIcon(t, size: compact ? 52 : 72),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(t.name, style: pixelText(compact ? 16 : 20, weight: FontWeight.w700)),
            PixelBox(
              color: color,
              border: color,
              shadow: false,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(rarityName(t.rarity), style: pixelText(12, color: Colors.white)),
            ),
          ]),
          if (t.story.isNotEmpty && !compact) MathText(t.story, style: pixelText(14, color: Px.shadow)),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
            Text(boostText(t), style: pixelText(compact ? 13 : 15, color: Px.okText, weight: FontWeight.w700)),
            const Sprite('monster_coin', width: 16, height: 16),
            Text('${t.value}', style: pixelText(compact ? 13 : 15, color: Px.amber, weight: FontWeight.w700)),
          ]),
        ]),
      ),
    ]);
  }
}

/// 开宝箱：先是关着的箱子，一会儿打开，宝藏跳出来；升级了再加一行
class TreasureReveal extends StatefulWidget {
  const TreasureReveal({super.key, required this.t, this.levelUp});
  final Treasure t;
  final int? levelUp;

  @override
  State<TreasureReveal> createState() => _TreasureRevealState();
}

class _TreasureRevealState extends State<TreasureReveal> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _open = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final legend = t.rarity == 'legend' || t.rarity == 'epic';
    return PixelBox(
      color: Color.alphaBlend(rarityColors[t.rarity]!.withValues(alpha: 0.12), Px.panel),
      border: rarityColors[t.rarity]!,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Sprite(_open ? 'monster_chest_open' : 'monster_chest', width: 80, height: 80),
        const SizedBox(width: 14),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: !_open
                ? Text(tr('寶箱裡有什麼呢……', "What's in the chest…", '¿Qué habrá en el cofre…?'), key: const ValueKey('closed'), style: pixelText(18, color: Px.shadow))
                : Column(key: const ValueKey('open'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      legend ? tr('哇！發現了一件${rarityName(t.rarity)}寶藏！', 'Wow! You found a ${rarityName(t.rarity)} treasure!', '¡Hala! ¡Has encontrado un tesoro ${rarityName(t.rarity)}!') : tr('獲得寶藏！', 'Treasure found!', '¡Tesoro encontrado!'),
                      style: pixelText(16, color: rarityColors[t.rarity]!, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TreasureCard(t),
                    if (widget.levelUp != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        tr('升級啦！Benny 現在是 Lv.${widget.levelUp}', 'Level up! Benny is now Lv.${widget.levelUp}', '¡Subes de nivel! Benny ya es Nv.${widget.levelUp}'),
                        style: pixelText(18, color: Px.amber, weight: FontWeight.w700),
                      ),
                    ],
                  ]),
          ),
        ),
      ]),
    );
  }
}

/// 首页的冒险者卡片：Benny、等级、称号、六项能力、金币、宝藏数
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.player, required this.onOpenChest});
  final Player player;
  final VoidCallback onOpenChest;

  @override
  Widget build(BuildContext context) {
    final g = GameData.instance;
    final stats = player.stats;
    final top = stats.values.fold(10, (a, b) => a > b ? a : b);
    final narrow = isNarrow(context);
    final coins = Row(mainAxisSize: MainAxisSize.min, children: [
      const Sprite('monster_coin', width: 20, height: 20),
      Text(' ${player.coins}   ', style: pixelText(16, color: Px.amber, weight: FontWeight.w700)),
      Text(tr('寶藏 ${player.owned.length} 件', '${player.owned.length} treasure${player.owned.length == 1 ? '' : 's'}', '${player.owned.length} tesoro${player.owned.length == 1 ? '' : 's'}'), style: pixelText(15, color: Px.shadow)),
    ]);
    final power = _Bar(
      value: player.progress,
      color: Px.sky,
      label: tr('能力 ${player.power} / 下一級 ${Player.need(player.level + 1)}', 'Power ${player.power} / next level ${Player.need(player.level + 1)}', 'Poder ${player.power} / siguiente nivel ${Player.need(player.level + 1)}'),
    );
    final chest = GestureDetector(
      onTap: onOpenChest,
      child: Column(children: [
        Sprite('monster_chest', width: narrow ? 48 : 64, height: narrow ? 48 : 64),
        Text(tr('寶藏箱', 'Treasures', 'Tesoros'), style: pixelText(14, color: Px.sky)),
      ]),
    );
    // 六项能力：平板上两三列，手机上一项一行
    Widget statRow(String id, double width) => SizedBox(
          width: width,
          child: Row(children: [
            SizedBox(width: narrow ? 128 : 104, child: Text(g.statName(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: pixelText(14))),
            Expanded(child: _Bar(value: (stats[id] ?? 0) / top, color: Px.grass, label: '${stats[id] ?? 0}')),
          ]),
        );

    if (narrow) {
      return PixelBox(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Column(children: [
              const Benny(height: 64, happy: true),
              Text('Lv.${player.level}', style: pixelText(18, weight: FontWeight.w700, color: Px.sky)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(player.title, style: pixelText(18, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, child: coins),
              ]),
            ),
            const SizedBox(width: 8),
            chest,
          ]),
          const SizedBox(height: 8),
          power,
          const SizedBox(height: 8),
          for (final st in g.stats) Padding(padding: const EdgeInsets.only(bottom: 4), child: statRow(st.id, double.infinity)),
        ]),
      );
    }
    return PixelBox(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          const Benny(height: 90, happy: true),
          const SizedBox(height: 4),
          Text('Lv.${player.level}', style: pixelText(22, weight: FontWeight.w700, color: Px.sky)),
        ]),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(player.title, style: pixelText(20, weight: FontWeight.w700))),
              coins,
            ]),
            const SizedBox(height: 4),
            power,
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 6, children: [for (final st in g.stats) statRow(st.id, 240)]),
          ]),
        ),
        const SizedBox(width: 12),
        chest,
      ]),
    );
  }
}

/// 像素进度条
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, required this.label});
  final double value;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 20,
        child: Stack(children: [
          Positioned.fill(child: Container(decoration: BoxDecoration(color: Px.paperDim, border: Border.all(color: Px.ink, width: 2)))),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: value.clamp(0, 1).toDouble(), child: ColoredBox(color: color)),
            ),
          ),
          Center(child: Text(label, style: pixelText(12, weight: FontWeight.w700))),
        ]),
      );
}
