import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../../i18n.dart';
import '../../logic/hunt_controller.dart';
import '../../services/local_db.dart';
import '../../theme/pixel_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/math_text.dart';
import '../../game/monster_art.dart';
import '../../widgets/hunt_card.dart' show summaryMonster;
import '../../widgets/turtles.dart';
import 'hunt_screen.dart';

/// 拍题：题目和解答写在一起，可以按顺序拍好几张；再选这道题的情况
class CaptureView extends StatefulWidget {
  const CaptureView({super.key, required this.c});
  final HuntController c;

  @override
  State<CaptureView> createState() => _CaptureViewState();
}

class _CaptureViewState extends State<CaptureView> {
  late final _note = TextEditingController(text: widget.c.session.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TurtlesSay(
          c.session.demo
              ? tr('這是示例模式：不用拍照，選一下情況，直接召喚怪獸圖鑑看看。', "This is demo mode: no photo needed. Pick how it went, then summon the Monster Guide.", 'Esto es el modo de ejemplo: no hace falta foto. Elige cómo te fue y llama a la Guía de Monstruos.')
              : tr('把那道讓你頭疼的題連同你寫的解答一起拍下來。一張紙寫不下就接著拍，按順序拍。',
                  'Snap the problem that gave you trouble, together with your working. If it runs onto more pages, keep snapping in order.', 'Haz una foto del problema que te dio problemas, junto con tu resolución. Si ocupa varias hojas, sigue haciendo fotos en orden.'),
        ),
        gap,
        if (!c.session.demo) PhotoPages(photos: c.problemPhotos, title: tr('題目和我的解答', 'Problem and my working', 'El problema y mi resolución'),
            hint: tr('讓字佔滿畫面，光線亮一點。寫了好幾張就按順序都拍上，可以點照片放大檢查。', 'Fill the frame with the writing and use good light. Several pages? Snap them in order — tap a photo to zoom and check.', 'Que la escritura llene la foto y que haya buena luz. ¿Varias hojas? Hazles foto en orden; toca una foto para ampliarla y revisarla.')),
        gap,
        Text(tr('這道題你…', 'On this problem you…', 'En este problema tú…'), style: pixelText(20, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 10, children: [
          for (final s in const ['完全不会', '做了但不确定对不对', '做错了'])
            PxButton(statusLabel(s), type: c.session.status == s ? NesButtonType.primary : NesButtonType.normal, onPressed: () => c.setStatus(s)),
        ]),
        gap,
        Text(tr('還想告訴小加和小減什麼？（可以不填）', 'Anything else to tell Plus and Minus? (optional)', '¿Algo más que contarles a Más y Menos? (opcional)'), style: pixelText(16)),
        const SizedBox(height: 6),
        TextField(
          controller: _note,
          maxLength: 300,
          style: pixelText(16),
          decoration: InputDecoration(hintText: tr('比如：第二步不知道怎麼去括號', "e.g. I didn't know how to remove the brackets in step 2", 'p. ej. no sabía quitar los paréntesis en el paso 2')),
          onChanged: c.setNote,
        ),
        gap,
        if (c.seenBefore != null) ...[_SeenBefore(c: c, h: c.seenBefore!), gap],
        Align(
          alignment: Alignment.centerRight,
          child: PxButton(tr('召喚怪獸圖鑑（開始分析）', 'Summon the Monster Guide (analyze)', 'Llamar a la Guía de Monstruos (analizar)'), big: true, icon: NesIcons.magnifier, onPressed: c.canAnalyze && c.seenBefore == null ? c.analyze : null),
        ),
        if (!c.session.demo) const Padding(padding: EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerRight, child: ChatGptPlanTag())),
        if (!c.canAnalyze)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(c.session.demo ? tr('先選一下這道題的情況。', 'Pick how this problem went first.', 'Primero elige cómo te fue con este problema.') : tr('拍好照片、選好情況就可以開始。', 'Take the photos and pick how it went to start.', 'Haz las fotos y elige cómo te fue para empezar.'), textAlign: TextAlign.right, style: pixelText(14, color: Px.shadow)),
          ),
      ],
    );
  }
}

/// 这道题以前拍过：问一下是不是这道，是就直接打开以前的图鉴和修炼（不调用 GPT）
class _SeenBefore extends StatelessWidget {
  const _SeenBefore({required this.c, required this.h});
  final HuntController c;
  final HuntSummary h;

  @override
  Widget build(BuildContext context) {
    final monster = summaryMonster(h);
    final when = DateTime.fromMillisecondsSinceEpoch(h.createdAt);
    return Panel(
      title: tr('這隻怪獸好像以前抓到過', 'Looks like we caught this monster before', 'Parece que ya atrapamos a este monstruo'),
      color: Px.sunLight,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MonsterAvatar(monster, size: 72, defeated: h.done),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                tr('${when.month}月${when.day}日抓到的${monster.displayName}${h.done ? '（已經打敗過）' : ''}',
                    '${monster.displayName}, caught on ${when.month}/${when.day}${h.done ? ' (already beaten)' : ''}', '${monster.displayName}, atrapado el ${when.day}/${when.month}${h.done ? ' (ya vencido)' : ''}'),
                style: pixelText(16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              MathText(h.problemText, style: pixelText(17)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        TurtlesSay(tr('是這道題嗎？是的話直接開啟以前的圖鑑和修煉，不用再等 AI。', 'Is it this one? If so, we open the old guide and training right away — no waiting for AI.', '¿Es este? Si es así, abrimos la guía y el entrenamiento de antes al momento, sin esperar a la IA.'), mood: TurtleMood.thinking, size: 56),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 10, children: [
          PxButton(tr('不是，重新分析', "No, analyze it fresh", 'No, analizarlo de nuevo'), type: NesButtonType.normal, onPressed: c.analyzeAnyway),
          PxButton(tr('就是這道，直接開啟', "Yes, that's it — open it", 'Sí, es ese: abrirlo'), big: true, icon: NesIcons.openFolder, onPressed: () => Navigator.of(context).pop(OpenArchived(h.pid))),
        ]),
      ]),
    );
  }
}

/// "这道题你…"的三个选项（值是中文，发给 GPT、记进学习事件）
String statusLabel(String s) => switch (s) {
      '完全不会' => tr('完全不會', "I couldn't do it", 'No sabía hacerlo'),
      '做了但不确定对不对' => tr('做了但不確定對不對', 'Did it, not sure', 'Lo hice, pero no estoy seguro'),
      '做错了' => tr('做錯了', 'Got it wrong', 'Me salió mal'),
      _ => s,
    };
