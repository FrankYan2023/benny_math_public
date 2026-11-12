import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../i18n.dart';
import '../logic/coach_controller.dart';
import '../models/jail.dart';
import '../theme/pixel_theme.dart';
import 'common.dart';
import 'turtles.dart';
import 'math_text.dart';

/// 一步一步来：第 1 步讲给 Benny 看；后面每一步先只给"这一步要做什么"和提示，他在纸上做、拍照检查，
/// 对了直接看这一步的讲解，错了先说明错在哪里、再看正确的这一步，然后做下一步。全部做完才给出答案。
class CoachPanel extends StatelessWidget {
  const CoachPanel({super.key, required this.k, this.doneNote});
  final CoachController k;

  /// 全部做完以后的说明（打怪页面里说"关进了怪兽监狱"）
  final String? doneNote;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: k, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final c = k.c;
    final steps = c.steps;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        title: tr('一步一步來', 'Step by step', 'Paso a paso'),
        color: Px.skyLight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!c.hasSteps)
            TurtlesSay(
              tr('不會沒關係，我們不直接看答案。小加和小減把這道題拆成一小步一小步：第 1 步講給你看，後面每一步你先自己做，拍照給我們檢查。',
                  "Stuck? That's fine — no peeking at the answer. Plus and Minus will break this into small steps: we show you step 1, then you try each next step yourself and snap a photo for us to check.", '¿Atascado? No pasa nada: sin mirar la respuesta. Más y Menos dividirán esto en pasos pequeños: te enseñamos el paso 1 y luego intentas tú cada paso siguiente y nos haces una foto para revisarlo.'),
              mood: TurtleMood.thinking,
              size: 64,
            )
          else
            _StepChips(c: c),
          if (k.error != null) ...[const SizedBox(height: 12), CoachError(k: k)],
          if (k.busy != null) ...[const SizedBox(height: 12), CoachBusy(k: k)],
          if (!c.hasSteps && k.busy == null) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: PxButton(tr('開始一步一步來', "Let's go step by step", 'Vamos paso a paso'), big: true, onPressed: k.start)),
          ],
        ]),
      ),
      if (c.hasSteps) ...[
        for (var i = 0; i < c.at && i < steps.length; i++) ...[const SizedBox(height: 14), _DoneStep(i: i, step: steps[i], log: i < c.log.length ? c.log[i] : const {})],
        const SizedBox(height: 14),
        if (!c.coachDone) _CurrentStep(k: k) else _Finished(c: c, note: doneNote),
      ],
    ]);
  }
}

/// 每一步一格：自己做对 ✓、做错了 ✗、讲给他看的 · 、正在做的高亮
class _StepChips extends StatelessWidget {
  const _StepChips({required this.c});
  final JailCase c;

  @override
  Widget build(BuildContext context) {
    final n = c.steps.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        c.coachDone
            ? tr('全部 $n 步做完了！你自己做對了 ${c.stepsByHimself} 步。', 'All $n steps done! You got ${c.stepsByHimself} right on your own.', '¡Los $n pasos hechos! Acertaste ${c.stepsByHimself} tú solo.')
            : tr('一共 $n 步，現在做第 ${c.at + 1} 步。', '$n steps in all. Now on step ${c.at + 1}.', '$n pasos en total. Ahora vas por el paso ${c.at + 1}.'),
        style: pixelText(17, weight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < n; i++)
          () {
            final how = i < c.at && i < c.log.length ? '${c.log[i]['how']}' : '';
            final current = i == c.at && !c.coachDone;
            final (bg, mark) = switch (how) {
              'right' => (Px.grassLight, Mark.ok),
              'wrong' => (Px.brickLight, Mark.bad),
              'shown' || 'told' => (Px.paperDim, Mark.none),
              _ => (current ? Px.sunLight : Px.panel, null),
            };
            return PixelBox(
              color: bg,
              border: current ? Px.sky : Px.ink,
              shadow: current,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('第 ${i + 1} 步', 'Step ${i + 1}', 'Paso ${i + 1}'), style: pixelText(15, weight: current ? FontWeight.w700 : FontWeight.w400)),
                if (mark != null && mark != Mark.none) ...[const SizedBox(width: 6), MarkIcon(mark, size: 16)],
              ]),
            );
          }(),
      ]),
    ]);
  }
}

/// 做完的一步：他写的（对 / 错在哪里）+ 这一步的详细讲解
class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.i, required this.step, required this.log});
  final int i;
  final Map<String, dynamic> step;
  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final how = '${log['how'] ?? 'told'}';
    final seen = '${log['seen'] ?? ''}'.trim();
    final (title, color) = switch (how) {
      'right' => (tr('第 ${i + 1} 步 · 你自己做對了', 'Step ${i + 1} · you got it', 'Paso ${i + 1} · lo lograste'), Px.grassLight),
      'wrong' => (tr('第 ${i + 1} 步 · 看看正確的這一步', 'Step ${i + 1} · here is the right way', 'Paso ${i + 1} · así se hace bien'), Px.panel),
      'shown' => (tr('第 ${i + 1} 步 · 小加和小減講給你看', 'Step ${i + 1} · Plus and Minus show you', 'Paso ${i + 1} · Más y Menos te lo enseñan'), Px.panel),
      _ => (tr('第 ${i + 1} 步 · 小加和小減講給你聽', 'Step ${i + 1} · Plus and Minus explain it', 'Paso ${i + 1} · Más y Menos te lo explican'), Px.panel),
    };
    return Panel(
      title: title,
      color: color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MathText('${step['goal']}', style: pixelText(18, weight: FontWeight.w700)),
        if (how == 'right') ...[
          const SizedBox(height: 8),
          Verdict(Mark.ok, seen.isEmpty ? tr('做對了！', 'Correct!', '¡Correcto!') : tr('做對了！你寫的：$seen', 'Correct! You wrote: $seen', '¡Correcto! Escribiste: $seen')),
          if ('${log['comment'] ?? ''}'.isNotEmpty) MathText('${log['comment']}', style: pixelText(15, color: Px.okText)),
        ],
        if (how == 'wrong') ...[
          const SizedBox(height: 8),
          PixelBox(
            color: Px.brickLight,
            shadow: false,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Verdict(Mark.bad, seen.isEmpty ? tr('這一步不對', 'This step is not right', 'Este paso no está bien') : tr('你寫的：$seen', 'You wrote: $seen', 'Escribiste: $seen')),
              const SizedBox(height: 4),
              MathText('${tr('錯在哪裡：', 'What went wrong: ', 'Qué falló: ')}${log['where'] ?? ''}', style: pixelText(16)),
              if ('${log['comment'] ?? ''}'.isNotEmpty) ...[const SizedBox(height: 4), MathText('${log['comment']}', style: pixelText(15, color: Px.shadow))],
            ]),
          ),
          const SizedBox(height: 8),
          Text(tr('正確的這一步：', 'The right way:', 'La forma correcta:'), style: pixelText(15, color: Px.shadow, weight: FontWeight.w700)),
        ],
        const SizedBox(height: 8),
        MathText('${step['explain']}', style: pixelText(17)),
        const SizedBox(height: 8),
        PixelBox(
          color: Px.paperDim,
          shadow: false,
          padding: const EdgeInsets.all(10),
          child: MathText('${tr('這一步寫成：', 'Write: ', 'Escribe: ')}${step['result']}', style: pixelText(18, weight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// 正在做的一步：只给"要做什么"和提示，Benny 自己做，拍照检查
class _CurrentStep extends StatelessWidget {
  const _CurrentStep({required this.k});
  final CoachController k;

  @override
  Widget build(BuildContext context) {
    final c = k.c;
    final i = c.at;
    final step = c.steps[i];
    final check = k.lastCheck;
    final unclear = check != null && check['step'] == i + 1 && check['verdict'] == '看不清';
    return Panel(
      title: tr('第 ${i + 1} 步 · 輪到你了', 'Step ${i + 1} · your turn', 'Paso ${i + 1} · te toca'),
      color: Px.sunLight,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MathText('${step['goal']}', style: pixelText(20, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        PixelBox(
          color: Px.panel,
          shadow: false,
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('提示  ', 'Hint  ', 'Pista  '), style: pixelText(15, color: Px.amber, weight: FontWeight.w700)),
            Expanded(child: MathText('${step['hint']}', style: pixelText(17))),
          ]),
        ),
        const SizedBox(height: 12),
        Text(tr('在紙上接著前面寫出這一步，然後拍照。', 'Write this step on paper, carrying on from the steps above, then snap a photo.', 'Escribe este paso en papel, siguiendo los pasos de arriba, y luego hazle una foto.'), style: pixelText(15, color: Px.shadow)),
        if (unclear) ...[
          const SizedBox(height: 10),
          Verdict(Mark.warn, '${tr('照片看不清：', "The photo isn't clear: ", 'La foto no se ve bien: ')}${check['where'] ?? ''}'),
        ],
        const SizedBox(height: 12),
        if (k.demo)
          Text(tr('示例模式不用拍照，直接點"檢查這一步"。', 'Demo mode: no photo needed — just tap "Check this step".', 'Modo de ejemplo: no hace falta foto; solo toca «Revisar este paso».'), style: pixelText(14, color: Px.amber))
        else
          PhotoPages(
            photos: k.photos,
            title: tr('我的第 ${i + 1} 步', 'My step ${i + 1}', 'Mi paso ${i + 1}'),
            hint: tr('拍你剛寫的這一步（前面幾步拍進去也沒關係）。', 'Snap the step you just wrote (it is fine if earlier steps are in the photo too).', 'Haz foto del paso que acabas de escribir (no pasa nada si salen también los pasos anteriores).'),
          ),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 10, children: [
          PxButton(tr('這一步我不會，講給我聽', "I can't do this step — explain it", 'No me sale este paso: explícamelo'), type: NesButtonType.normal, onPressed: k.busy == null ? k.tellStep : null),
          PxButton(tr('檢查這一步', 'Check this step', 'Revisar este paso'), big: true, icon: NesIcons.magnifier, onPressed: k.canSubmit && k.busy == null ? k.submitStep : null),
        ]),
      ]),
    );
  }
}

/// 全部做完：最后的答案和整道题的思路
class _Finished extends StatelessWidget {
  const _Finished({required this.c, this.note});
  final JailCase c;
  final String? note;

  @override
  Widget build(BuildContext context) => Panel(
        title: tr('答案', 'Answer', 'Respuesta'),
        color: Px.grassLight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MathText('${tr('最後的答案：', 'Final answer: ', 'Respuesta final: ')}${c.coach?['final_answer'] ?? c.correctAnswer}', style: pixelText(20, weight: FontWeight.w700)),
          if ('${c.coach?['idea'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            MathText('${tr('這道題的思路：', 'The big idea: ', 'La idea clave: ')}${c.coach!['idea']}', style: pixelText(17)),
          ],
          if (note != null) ...[const SizedBox(height: 12), Text(note!, style: pixelText(15, color: Px.shadow))],
        ]),
      );
}

class CoachBusy extends StatelessWidget {
  const CoachBusy({super.key, required this.k});
  final CoachController k;

  @override
  Widget build(BuildContext context) => PixelBox(
        color: Px.panel,
        shadow: false,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Turtles(size: 48, mood: TurtleMood.thinking),
          const SizedBox(width: 12),
          Expanded(child: Text(k.busy!.label, style: pixelText(16))),
          const NesHourglassLoadingIndicator(),
          const SizedBox(width: 12),
          PxButton(tr('取消', 'Cancel', 'Cancelar'), type: NesButtonType.normal, onPressed: k.cancel),
        ]),
      );
}

class CoachError extends StatelessWidget {
  const CoachError({super.key, required this.k});
  final CoachController k;

  @override
  Widget build(BuildContext context) => PixelBox(
        color: Px.brickLight,
        shadow: false,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Turtles(size: 48, mood: TurtleMood.oops),
          const SizedBox(width: 12),
          Expanded(child: Text(k.error!, style: pixelText(15))),
          if (k.retry != null) ...[PxButton(tr('重試', 'Retry', 'Reintentar'), onPressed: () => k.retry!()), const SizedBox(width: 8)],
          PxButton(tr('關閉', 'Close', 'Cerrar'), type: NesButtonType.normal, onPressed: k.dismissError),
        ]),
      );
}
