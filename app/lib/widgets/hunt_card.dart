import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../game/monster.dart';
import '../game/monster_art.dart';
import '../i18n.dart';
import '../models/knowledge.dart';
import '../services/local_db.dart';
import '../theme/pixel_theme.dart';
import 'common.dart';
import 'math_text.dart';

/// 这道题的怪兽（存档里有就用存档的，旧的题按题目编号算出一只）
MonsterTraits summaryMonster(HuntSummary h) => MonsterTraits.fromJson(h.monster) ?? MonsterTraits.fromSeed(h.pid, h.errorType);

/// 怪兽屋里的一张卡：哪只怪兽、什么题、打到哪一步了；可以订正、放生
class HuntCard extends StatelessWidget {
  const HuntCard({super.key, required this.h, required this.kb, required this.onTap, this.onCorrect, this.onRelease});
  final HuntSummary h;
  final Knowledge kb;
  final VoidCallback onTap;
  final VoidCallback? onCorrect;
  final VoidCallback? onRelease;

  @override
  Widget build(BuildContext context) {
    final monster = summaryMonster(h);
    final when = DateTime.fromMillisecondsSinceEpoch(h.createdAt);
    final (stage, color) = h.done
        ? (tr('已打敗', 'Beaten', 'Vencido'), Px.okText)
        : switch (h.stage) {
            'boss' => (tr('Boss 戰', 'Boss fight', 'Batalla final'), Px.brick),
            'learn' => (tr('修煉中', 'Training', 'Entrenamiento'), Px.sky),
            _ => (tr('剛發現', 'Just found', 'Recién encontrado'), Px.amber),
          };
    final kps = Text(
      h.kpIds.isEmpty ? tr('沒有要修煉的知識點', 'No topics to train', 'Sin temas que entrenar') : h.kpIds.map((id) => kb.byId[id]?.label ?? id).join(tr('、', ', ', ', ')),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: pixelText(13, color: Px.shadow),
    );
    return GestureDetector(
      onTap: onTap,
      child: PixelBox(
        width: 270,
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            MonsterAvatar(monster, size: 56, defeated: h.done),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(monster.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: pixelText(15, weight: FontWeight.w700)),
                Text('${tr('${when.month}月${when.day}日', '${when.month}/${when.day}', '${when.day}/${when.month}')} · $stage', style: pixelText(13, color: color)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Expanded(child: ClipRect(child: MathText(h.problemText, style: pixelText(14)))),
          if (onRelease == null)
            Row(children: [
              Expanded(child: kps),
              if (onCorrect != null) ...[
                const SizedBox(width: 6),
                PxButton(tr('訂正', 'Correct it', 'Corregir'), type: NesButtonType.warning, onPressed: onCorrect),
              ],
            ])
          else ...[
            kps,
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              PxButton(tr('放生', 'Release', 'Liberar'), type: NesButtonType.normal, onPressed: onRelease),
              if (onCorrect != null) ...[
                const SizedBox(width: 8),
                PxButton(tr('訂正', 'Correct it', 'Corregir'), type: NesButtonType.warning, onPressed: onCorrect),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}
