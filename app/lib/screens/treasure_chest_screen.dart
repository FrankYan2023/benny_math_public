import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../game/game_widgets.dart';
import '../game/player.dart';
import '../game/treasure.dart';
import '../game/treasure_art.dart';
import '../i18n.dart';
import '../services/local_db.dart';
import '../services/settings.dart';
import '../theme/pixel_theme.dart';
import '../widgets/common.dart';
import '../widgets/sprite.dart';

/// 宝藏箱：Benny 手里的宝藏，可以按稀有度看，也可以卖掉换金币（加过的能力保留）
class TreasureChestScreen extends StatefulWidget {
  const TreasureChestScreen({super.key, required this.player, required this.settings});
  final Player player;
  final AppSettings settings;

  @override
  State<TreasureChestScreen> createState() => _TreasureChestScreenState();
}

class _TreasureChestScreenState extends State<TreasureChestScreen> {
  String _filter = 'all';
  late Player _p = widget.player;

  Future<void> _sell(Treasure t) async {
    final yes = await confirmBox(
      context,
      leading: TreasureIcon(t, size: 72),
      title: tr('把「${t.name}」賣掉？', 'Sell ${t.name}?', '¿Vender ${t.name}?'),
      body: tr('賣給商人能換 ${t.value} 金幣。賣掉以後它就不在寶藏箱裡了，它給你加的能力還保留。',
          "The merchant pays ${t.value} coins. It leaves your chest, but the power it gave you stays.", 'El mercader paga ${t.value} monedas. Saldrá de tu cofre, pero el poder que te dio se queda.'),
      ok: tr('賣掉', 'Sell', 'Vender'),
      cancel: tr('留著', 'Keep it', 'Quedármelo'),
    );
    if (!yes) return;
    final sold = await PlayerStore.sell(t.id);
    if (sold == null) return;
    await LocalDb.instance.record('treasure.sold', {'treasureId': t.id});
    final p = await PlayerStore.load();
    if (!mounted) return;
    setState(() => _p = p);
    NesSnackbar.show(context, text: tr('賣掉了！+${t.value} 金幣', 'Sold! +${t.value} coins', '¡Vendido! +${t.value} monedas'), type: NesSnackbarType.success);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final all = p.owned.reversed.toList();
    final sold = p.soldList;
    final shown = _filter == 'all' ? all : all.where((t) => t.rarity == _filter).toList();
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: pagePadding(context), children: [
          Row(children: [
            PxButton(tr('← 返回', '← Back', '← Volver'), type: NesButtonType.normal, onPressed: () => Navigator.of(context).pop()),
            const SizedBox(width: 16),
            Expanded(child: Text(tr('寶藏箱', 'Treasure Chest', 'Cofre del tesoro'), style: pixelText(isNarrow(context) ? 22 : 28, weight: FontWeight.w700))),
          ]),
          const SizedBox(height: 16),
          PlayerCard(player: p, onOpenChest: () {}),
          const SizedBox(height: 12),
          Text(
            tr('每隻怪獸、每個村莊都藏著一件寶藏，把修煉打完就能拿到。不想要的寶藏可以賣掉換金幣，加過的能力不會減少。',
                'Every monster and every village hides one treasure — finish the training to get it. Sell the ones you do not need for coins; your power stays.', 'Cada monstruo y cada aldea esconden un tesoro: termina el entrenamiento para conseguirlo. Vende los que no necesites por monedas; tu poder se queda.'),
            style: pixelText(15, color: Px.shadow),
          ),
          if (sold.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Sprite('monster_coin', width: 16, height: 16),
                const SizedBox(width: 6),
                Text(tr('已經賣掉 ${sold.length} 件，換來 ${p.coins} 金幣', 'Sold ${sold.length} for ${p.coins} coins', 'Vendidos ${sold.length} por ${p.coins} monedas'), style: pixelText(15, color: Px.amber, weight: FontWeight.w700)),
              ]),
            ),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final r in ['all', ...rarityOrder.reversed])
              PxButton(
                r == 'all' ? tr('全部 ${all.length}', 'All ${all.length}', 'Todos ${all.length}') : '${rarityName(r)} ${all.where((t) => t.rarity == r).length}',
                type: _filter == r ? NesButtonType.primary : NesButtonType.normal,
                onPressed: () => setState(() => _filter = r),
              ),
          ]),
          const SizedBox(height: 16),
          if (all.isEmpty)
            Text(
              sold.isEmpty
                  ? tr('還沒有寶藏。修煉完一隻怪獸或者一個村莊就能拿到。', 'No treasures yet. Finish training on a monster or a village to earn one.', 'Todavía no tienes tesoros. Termina el entrenamiento de un monstruo o de una aldea para ganar uno.')
                  : tr('寶藏箱空了，寶藏都賣掉了。', 'The chest is empty — everything has been sold.', 'El cofre está vacío: lo has vendido todo.'),
              style: pixelText(16, color: Px.shadow),
            ),
          Wrap(spacing: 14, runSpacing: 14, children: [
            for (final t in shown)
              SizedBox(
                width: 340,
                child: Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TreasureCard(t, compact: true),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: PxButton(tr('賣掉換 ${t.value} 金幣', 'Sell for ${t.value} coins', 'Vender por ${t.value} monedas'), type: NesButtonType.warning, onPressed: () => _sell(t)),
                    ),
                  ]),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
