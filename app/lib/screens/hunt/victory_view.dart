import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../../game/game_widgets.dart';
import '../../game/monster_art.dart';
import '../../game/treasure.dart';
import '../../i18n.dart';
import '../../logic/hunt_controller.dart';
import '../../models/hunt.dart';
import '../../theme/pixel_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/math_text.dart';
import '../../widgets/turtles.dart';
import 'hunt_screen.dart';

/// 结束：这次修炼了什么，标准解法，回地图
class VictoryView extends StatefulWidget {
  const VictoryView({super.key, required this.c});
  final HuntController c;

  @override
  State<VictoryView> createState() => _VictoryViewState();
}

class _VictoryViewState extends State<VictoryView> {
  bool _showSolution = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final a = c.session.analysis!;
    final monster = c.session.monsterTraits;
    // 这只怪兽的宝藏（一只怪兽只有一件）
    final treasure = c.session.monsterTreasure;
    final learned = c.session.queue;
    final won = c.session.bossWon || (a['is_correct'] == true && learned.isEmpty);

    Future<void> leave() async {
      await SessionStore.clear();
      if (context.mounted) Navigator.of(context).pop(true);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        color: won ? Px.grassLight : null,
        child: LeadRow(gap: 16, lead: [const Turtles(size: 120, mood: TurtleMood.happy), if (learned.isNotEmpty || a['is_correct'] != true) ...[MonsterAvatar(monster, size: 96, defeated: won), const SizedBox(width: 16)]], child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(won ? (learned.isEmpty && a['is_correct'] == true ? tr('本來就做對了！', 'You had it right all along!', '¡Ya lo tenías bien desde el principio!') : tr('打敗了${monster.displayName}！', 'You beat the ${monster.displayName}!', '¡Has vencido a ${monster.displayName}!')) : tr('這次先到這裡', "That's it for now", 'Por ahora, ya está'), style: pixelText(28, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(won ? tr('它已經住進你的怪獸屋，隨時可以回來再打一遍。', 'It now lives in your Monster House. Come back and fight it again any time.', 'Ahora vive en tu Casa de los Monstruos. Vuelve a luchar contra él cuando quieras.') : tr('沒關係，下次再來挑戰它。', 'No worries — challenge it again next time.', 'No pasa nada: la próxima vez vuelve a desafiarlo.'), style: pixelText(17, color: Px.shadow)),
            ])),
      ),
      gap,
      if (learned.isNotEmpty) ...[
        Panel(
          title: tr('這次修煉的知識點', 'Topics trained', 'Temas entrenados'),
          child: Column(children: [
            for (final id in learned)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: KpLabel(c, id)),
                  Builder(builder: (_) {
                    final l = c.session.lessons[id];
                    if (l == null) return Text(tr('這次沒學', 'Not trained', 'Sin entrenar'), style: pixelText(15, color: Px.shadow));
                    final s = l.score();
                    return Text(tr('打倒 ${s.right}/${s.total} 只${s.passed ? ' · 過關' : ''}', 'Defeated ${s.right}/${s.total}${s.passed ? ' · passed' : ''}', 'Vencidos ${s.right}/${s.total}${s.passed ? ' · superado' : ''}'),
                        style: pixelText(15, color: s.passed ? Px.okText : Px.amber));
                  }),
                ]),
              ),
          ]),
        ),
        gap,
      ],
      if (treasure != null || c.lessonsLeft > 0) ...[
        Panel(
          title: tr('這隻怪獸的寶藏', "This monster's treasure", 'El tesoro de este monstruo'),
          child: treasure != null ? TreasureCard(Treasure.fromJson(treasure), compact: true) : HuntTreasure(c: c),
        ),
        gap,
      ],
      Panel(
        title: tr('標準解法', 'Model solution', 'Solución modelo'),
        child: _showSolution
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (i, st) in (a['solution_steps'] as List).indexed)
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: MathText('${i + 1}. $st', style: pixelText(18))),
                MathText('${tr('答案：', 'Answer: ', 'Respuesta: ')}${a['correct_answer']}', style: pixelText(19, weight: FontWeight.w700)),
              ])
            : Align(alignment: Alignment.centerLeft, child: PxButton(tr('開啟看看', 'Show it', 'Mostrarlo'), type: NesButtonType.normal, onPressed: () => setState(() => _showSolution = true))),
      ),
      gap,
      Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 10, children: [
        if (learned.isNotEmpty) PxButton(tr('回看修煉', 'Review training', 'Repasar el entrenamiento'), type: NesButtonType.normal, onPressed: c.backToLearning),
        PxButton(tr('回到冒險地圖', 'Back to the map', 'Volver al mapa'), big: true, icon: NesIcons.home, onPressed: leave),
      ]),
    ]);
  }
}
