import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../../i18n.dart';
import '../../logic/hunt_controller.dart';
import '../../models/hunt.dart';
import '../../theme/pixel_theme.dart';
import '../../widgets/coach_panel.dart';
import '../../widgets/common.dart';
import '../../widgets/math_text.dart';
import '../../widgets/monsters.dart';
import '../../widgets/turtles.dart';
import '../../widgets/sprite.dart';
import '../../widgets/visuals.dart';
import 'hunt_screen.dart';

/// 修炼：上面切换知识点，下面"讲解 / 例题 / 打小怪"三个标签随时切换
class LessonView extends StatelessWidget {
  const LessonView({super.key, required this.c});
  final HuntController c;

  @override
  Widget build(BuildContext context) {
    final s = c.session;
    final id = s.currentKp!;
    final l = s.lessons[id];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.isVillage)
        _VillageHead(c: c, id: id)
      else ...[
        _KpBar(c: c),
        const SizedBox(height: 14),
        KpLabel(c, id, size: 24),
      ],
      const SizedBox(height: 12),
      if (l == null)
        _Waiting(c: c)
      else ...[
        _Tabs(c: c, l: l),
        gap,
        switch (l.tab) {
          'example' => _ExampleTab(c: c, l: l),
          'practice' => _PracticeTab(key: ValueKey('$id/${l.q}'), c: c, l: l),
          _ => _CardTab(c: c, l: l),
        },
      ],
    ]);
  }
}

/// 村庄修炼的标题：哪个大陆、哪一章的村庄
class _VillageHead extends StatelessWidget {
  const _VillageHead({required this.c, required this.id});
  final HuntController c;
  final String id;

  @override
  Widget build(BuildContext context) {
    final kp = c.kb.byId[id];
    final module = c.kb.modules.where((m) => m.id == kp?.module).firstOrNull;
    return Row(children: [
      const Sprite('village_basic', width: 48, height: 48),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('${module?.termLabel ?? ''} · ${module?.label ?? ''} 的村莊', 'A village in ${module?.termLabel ?? ''} · ${module?.label ?? ''}', 'Una aldea de ${module?.termLabel ?? ''} · ${module?.label ?? ''}'), style: pixelText(14, color: Px.shadow)),
          KpLabel(c, id, size: 24),
        ]),
      ),
    ]);
  }
}

/// 修炼内容还在生成，或者生成失败
class _Waiting extends StatelessWidget {
  const _Waiting({required this.c});
  final HuntController c;

  @override
  Widget build(BuildContext context) {
    final err = c.trainingError;
    return Panel(
      child: Column(children: [
        TurtlesSay(err == null ? tr('小加和小減正在準備修煉內容，馬上就好。', 'Plus and Minus are preparing your training. Almost there.', 'Más y Menos están preparando tu entrenamiento. Ya casi está.') : tr('準備修煉內容時出了問題：$err', 'Something went wrong preparing the training: $err', 'Algo salió mal al preparar el entrenamiento: $err'), mood: err == null ? TurtleMood.thinking : TurtleMood.oops),
        if (err != null || !c.trainingLoading) ...[
          const SizedBox(height: 12),
          PxButton(tr('重新準備', 'Try again', 'Intentar de nuevo'), onPressed: c.waitForTraining),
        ],
      ]),
    );
  }
}

/// 知识点切换条：每个知识点一格，最后是 Boss 战
class _KpBar extends StatelessWidget {
  const _KpBar({required this.c});
  final HuntController c;

  @override
  Widget build(BuildContext context) {
    final s = c.session;
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final (i, id) in s.queue.indexed)
        _Chip(
          label: '${i + 1}. ${c.kpName(id)}',
          active: i == s.kpIndex,
          done: s.lessons[id]?.finished ?? false,
          onTap: () => c.openKp(i),
        ),
      _Chip(label: tr('Boss 戰', 'Boss', 'Jefe'), active: false, done: s.bossDone, boss: true, onTap: c.goToBoss),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.done, required this.onTap, this.boss = false});
  final String label;
  final bool active;
  final bool done;
  final bool boss;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Px.sky : (boss ? Px.brick : Px.ink);
    return GestureDetector(
      onTap: onTap,
      child: PixelBox(
        color: active ? Px.sky : Px.panel,
        border: color,
        shadow: active,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (done) ...[MarkIcon(Mark.ok, size: 16), const SizedBox(width: 6)],
          Text(label, style: pixelText(15, color: active ? Colors.white : color)),
        ]),
      ),
    );
  }
}

/// 讲解 / 例题 / 打小怪
class _Tabs extends StatelessWidget {
  const _Tabs({required this.c, required this.l});
  final HuntController c;
  final LessonState l;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('card', tr('講解', 'Lesson', 'Lección'), NesIcons.lamp),
      ('example', tr('例題', 'Example', 'Ejemplo'), NesIcons.edit),
      ('practice', tr('打小怪 ${l.defeated}/${l.practice.length}', 'Monsters ${l.defeated}/${l.practice.length}', 'Monstruos ${l.defeated}/${l.practice.length}'), NesIcons.sword),
    ];
    final narrow = isNarrow(context);
    return Row(children: [
      for (final (i, (key, name, icon)) in tabs.indexed) ...[
        if (i > 0) SizedBox(width: narrow ? 6 : 10),
        Expanded(
          child: NesButton(
            type: l.tab == key ? NesButtonType.primary : NesButtonType.normal,
            onPressed: () => c.setTab(key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (!narrow) ...[NesIcon(iconData: icon, size: const Size.square(20)), const SizedBox(width: 8)],
                  Text(name, style: pixelText(narrow ? 15 : 18, color: l.tab == key ? Colors.white : Px.ink)),
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

// ---------- 讲解 ----------
class _CardTab extends StatelessWidget {
  const _CardTab({required this.c, required this.l});
  final HuntController c;
  final LessonState l;

  @override
  Widget build(BuildContext context) {
    final card = l.card;
    final visual = card['visual'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        title: tr('小加和小減講解', 'Lesson from Plus and Minus', 'Lección de Más y Menos'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MathText('${card['one_liner']}', style: pixelText(22, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          MathText('${card['explanation']}', style: pixelText(17)),
          if (visual is Map) ...[const SizedBox(height: 16), LessonVisual(visual.cast<String, dynamic>())],
          if (card['mnemonic'] != null) ...[
            const SizedBox(height: 16),
            PixelBox(
              color: Px.paperDim,
              shadow: false,
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('口訣  ', 'Rhyme  ', 'Truco para recordar  '), style: pixelText(14, color: Px.shadow)),
                Expanded(child: MathText('${card['mnemonic']}', style: pixelText(17, weight: FontWeight.w700))),
              ]),
            ),
          ],
        ]),
      ),
      gap,
      Panel(title: tr('小心陷阱', 'Watch out', 'Cuidado'), color: Px.brickLight, child: MathText('${card['pitfall']}', style: pixelText(17))),
      gap,
      Panel(title: tr('和你那道題的關係', 'How it connects to your problem', 'Qué tiene que ver con tu problema'), child: MathText('${card['link_to_problem']}', style: pixelText(17))),
      gap,
      Align(alignment: Alignment.centerRight, child: PxButton(tr('看例題', 'See the example', 'Ver el ejemplo'), big: true, onPressed: () => c.setTab('example'))),
    ]);
  }
}

// ---------- 例题 ----------
class _ExampleTab extends StatelessWidget {
  const _ExampleTab({required this.c, required this.l});
  final HuntController c;
  final LessonState l;

  @override
  Widget build(BuildContext context) {
    final ex = l.example;
    final steps = (ex['steps'] as List).cast<Map>();
    final shown = steps.take(l.exStep).toList();
    final all = l.exStep >= steps.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        title: tr('例題', 'Example', 'Ejemplo'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MathText('${ex['problem']}', style: pixelText(20)),
          const SizedBox(height: 14),
          for (final (i, st) in shown.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}.', style: pixelText(18, color: Px.sky, weight: FontWeight.w700)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    MathText('${st['do']}', style: pixelText(19)),
                    MathText('${st['why']}', style: pixelText(15, color: Px.shadow)),
                  ]),
                ),
              ]),
            ),
          if (all) MathText('${tr('答案：', 'Answer: ', 'Respuesta: ')}${ex['answer']}', style: pixelText(18, weight: FontWeight.w700)),
        ]),
      ),
      gap,
      Align(
        alignment: Alignment.centerRight,
        child: all
            ? PxButton(tr('去打小怪', 'Fight the monsters', 'Luchar contra los monstruos'), big: true, icon: NesIcons.sword, onPressed: () => c.setTab('practice'))
            : PxButton(tr('下一步', 'Next step', 'Siguiente paso'), big: true, onPressed: c.nextExampleStep),
      ),
    ]);
  }
}

// ---------- 打小怪：每只只打一次，打完的可以回看 ----------
class _PracticeTab extends StatefulWidget {
  const _PracticeTab({super.key, required this.c, required this.l});
  final HuntController c;
  final LessonState l;

  @override
  State<_PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends State<_PracticeTab> {
  late final _answer = TextEditingController(text: widget.l.resultOf(widget.l.q).last);

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _insert(String k) {
    final sel = _answer.selection;
    final text = _answer.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _answer.value = TextEditingValue(text: text.replaceRange(start, end, k), selection: TextSelection.collapsed(offset: start + k.length));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final l = widget.l;
    final i = l.q.clamp(0, l.practice.length - 1);
    final q = l.practice[i];
    final r = l.resultOf(i);
    final level = levelOf(q);
    final enemy = practiceMonster(level);
    final choice = q['answer_type'] == '选择';
    final accepted = [for (final a in q['accepted_answers'] as List) '$a'];
    final lastQ = i + 1 >= l.practice.length;
    final gaveUp = r.revealed && !r.skipped && !r.override; // 放弃了、或者答错两次：不直接给答案，一步一步来
    final coach = gaveUp ? c.practiceCoach(l, i) : null;

    final feedback = <Widget>[
      if (r.override)
        Verdict(Mark.ok, tr('算你對：寫法不同，意思一樣', 'Counted as right: written differently, same meaning', 'Cuenta como correcta: escrita de otra forma, mismo significado'))
      else if (r.correct)
        Verdict(Mark.ok, tr('答對了${r.tries > 1 ? '（第二次）' : ''}！小怪被打倒了', 'Correct${r.tries > 1 ? ' (2nd try)' : ''}! Monster defeated', '¡Correcto${r.tries > 1 ? ' (2.º intento)' : ''}! Monstruo vencido'))
      else if (r.skipped)
        Text(tr('這隻小怪跳過了，不計分。', "Skipped — this one doesn't count.", 'Saltado: este no cuenta.'), style: pixelText(17, color: Px.amber))
      else if (r.tries > 0 && !r.revealed)
        Verdict(Mark.bad, tr('不對，再想想。可以看提示。', 'Not quite. Think again — you can use a hint.', 'Casi. Piénsalo otra vez: puedes usar una pista.')),
      if (gaveUp) ...[
        if (r.tries > 0) MathText('${tr('你的答案：', 'Your answer: ', 'Tu respuesta: ')}${r.last}', style: pixelText(16, color: Px.shadow)),
        if (coach?.c.coachDone ?? false)
          MathText('${tr('正確答案：', 'Correct answer: ', 'Respuesta correcta: ')}${accepted.isEmpty ? '' : accepted.first}', style: pixelText(18, color: Px.brick, weight: FontWeight.w700))
        else
          Text(tr('這隻小怪逃進了怪獸監獄。答案先不告訴你，下面一步一步把它學會。', "This monster escaped to the Monster Jail. No answer yet — let's learn it step by step below.", 'Este monstruo se escapó a la Cárcel de Monstruos. Todavía no te damos la respuesta: aprendámoslo paso a paso aquí abajo.'),
              style: pixelText(16, color: Px.brick)),
      ],
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // 4 只小怪：点哪只看哪只
      Row(children: [
        for (final (j, p) in l.practice.indexed) ...[
          if (j > 0) SizedBox(width: isNarrow(context) ? 6 : 10),
          Expanded(child: _EnemyTile(index: j, q: p, r: l.results[j], active: j == i, onTap: () => c.openQuestion(j))),
        ],
      ]),
      gap,
      Panel(
        child: Row(children: [
          MonsterSprite(enemy, size: 88, defeated: r.counted),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('第 ${i + 1} / ${l.practice.length} 只：${enemy.name}', 'Monster ${i + 1} / ${l.practice.length}: ${enemy.name}', 'Monstruo ${i + 1} / ${l.practice.length}: ${enemy.name}'), style: pixelText(20, weight: FontWeight.w700)),
              Text(tr('$level題 · 寫出最後的答案', '${levelLabel(level)} · write the final answer', '${levelLabel(level)} · escribe la respuesta final'), style: pixelText(15, color: Px.shadow)),
            ]),
          ),
          if (r.counted) const Turtles(size: 64, mood: TurtleMood.happy),
        ]),
      ),
      gap,
      Panel(title: tr('題目', 'Problem', 'Problema'), child: MathText('${q['problem']}', style: pixelText(21))),
      gap,
      if (!r.done) ...[
        if (choice)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (j, o) in (q['options'] as List).indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NesButton(
                  type: r.last == 'ABCD'[j] ? NesButtonType.primary : NesButtonType.normal,
                  onPressed: () => c.submitTyped('ABCD'[j]),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(children: [
                      Text('${'ABCD'[j]}.  ', style: pixelText(18, weight: FontWeight.w700, color: r.last == 'ABCD'[j] ? Colors.white : Px.sky)),
                      Expanded(child: MathText('$o', style: pixelText(18, color: r.last == 'ABCD'[j] ? Colors.white : Px.ink))),
                    ]),
                  ),
                ),
              ),
          ])
        else
          AnswerField(controller: _answer, onSubmit: c.submitTyped, onKey: _insert),
        gap,
      ],
      if (feedback.isNotEmpty) ...[Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: feedback)), gap],
      for (final (k, h) in [q['hint1'], q['hint2']].take(r.hints).indexed) ...[
        Panel(title: tr('提示 ${k + 1}', 'Hint ${k + 1}', 'Pista ${k + 1}'), color: Px.sunLight, child: MathText('$h', style: pixelText(17))),
        gap,
      ],
      if (gaveUp) ...[
        if (coach != null)
          CoachPanel(
            k: coach,
            doneNote: tr('這隻小怪關在怪獸監獄裡了。過一天去監獄裡自己再做一遍，在不同的兩天裡都做對就放它出來。',
                'This monster is locked in the Monster Jail. Come back another day and solve it on your own — right on two different days sets it free.', 'Este monstruo está encerrado en la Cárcel de Monstruos. Vuelve otro día y resuélvelo tú solo: si lo aciertas en dos días distintos, quedará libre.'),
          )
        else
          Align(alignment: Alignment.centerLeft, child: PxButton(tr('一步一步學會它', 'Learn it step by step', 'Aprenderlo paso a paso'), big: true, onPressed: c.coachPractice)),
        gap,
      ],
      if (r.done && !r.skipped && !gaveUp) ...[
        Panel(
          title: tr('解答', 'Solution', 'Solución'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (k, st) in (q['solution_steps'] as List).indexed)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: MathText('${k + 1}. $st', style: pixelText(17))),
          ]),
        ),
        gap,
      ],
      if (gaveUp && (coach?.c.coachDone ?? false) && r.tries > 0 && !choice && q['answer_type'] != '数值') ...[
        Align(alignment: Alignment.centerLeft, child: PxButton(tr('我的寫法不同，其實是對的', "I wrote it differently — it's actually right", 'Lo escribí de otra forma, pero en realidad está bien'), type: NesButtonType.normal, onPressed: c.markOverride)),
        gap,
      ],
      if (l.finished) ...[_LessonResult(c: c, l: l), gap],
      Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 10, children: [
        if (r.done) ...[
          if (!lastQ) PxButton(tr('下一隻', 'Next monster', 'Siguiente monstruo'), big: true, onPressed: c.nextQuestion),
        ] else ...[
          if (r.hints < 2) PxButton(tr('看提示 ${r.hints + 1}', 'Hint ${r.hints + 1}', 'Pista ${r.hints + 1}'), type: NesButtonType.warning, onPressed: c.hint),
          PxButton(tr('我放棄，一步一步來', 'I give up — go step by step', 'Me rindo: vamos paso a paso'), type: NesButtonType.normal, onPressed: c.reveal),
          if (!choice) PxButton(tr('出招（提交）', 'Attack! (submit)', '¡Ataque! (enviar)'), big: true, icon: NesIcons.sword, onPressed: () => c.submitTyped(_answer.text)),
        ],
      ]),
      if (!r.done) ...[
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: c.skip, child: Text(tr('這題答案有問題，跳過', 'Something is wrong with this one — skip', 'Este tiene algún problema: saltarlo'), style: pixelText(14, color: Px.shadow))),
        ),
      ],
    ]);
  }
}

/// 输入答案：输入框 + 常用符号键
class AnswerField extends StatelessWidget {
  const AnswerField({super.key, required this.controller, required this.onSubmit, required this.onKey});
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: controller,
          autocorrect: false,
          style: pixelText(24),
          decoration: InputDecoration(hintText: tr('寫最後的答案，比如 -3/4 或 x=2', 'Final answer, e.g. -3/4 or x=2', 'Respuesta final, p. ej. -3/4 o x=2')),
          onSubmitted: onSubmit,
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in const ['-', '/', '.', 'x=', '(', ')', '^'])
            NesButton(
              type: NesButtonType.normal,
              onPressed: () => onKey(k),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(k == '-' ? '−' : k, style: pixelText(20))),
            ),
        ]),
      ]);
}

/// 小怪格子：打倒 / 没打倒 / 还没打
class _EnemyTile extends StatelessWidget {
  const _EnemyTile({required this.index, required this.q, required this.r, required this.active, required this.onTap});
  final int index;
  final Map<String, dynamic> q;
  final QResult? r;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final level = levelOf(q);
    final (mark, color) = switch (r) {
      QResult(counted: true) => (Mark.ok, Px.grassLight),
      QResult(done: true) => (Mark.bad, Px.brickLight),
      _ => (null, Px.panel),
    };
    return GestureDetector(
      onTap: onTap,
      child: PixelBox(
        color: color,
        border: active ? Px.sky : Px.ink,
        shadow: active,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        // 手机上只放小怪和序号（难度在下面的题目里写着）
        child: isNarrow(context)
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                MonsterSprite(practiceMonster(level), size: 28, defeated: r?.counted ?? false),
                const SizedBox(width: 4),
                mark != null ? MarkIcon(mark, size: 16) : Text('${index + 1}', style: pixelText(15, weight: active ? FontWeight.w700 : FontWeight.w400)),
              ])
            : Row(children: [
                MonsterSprite(practiceMonster(level), size: 36, defeated: r?.counted ?? false),
                const SizedBox(width: 8),
                Expanded(child: Text('${index + 1}. ${levelLabel(level)}', style: pixelText(15, weight: active ? FontWeight.w700 : FontWeight.w400))),
                if (mark != null) MarkIcon(mark, size: 18),
              ]),
      ),
    );
  }
}

// ---------- 这个知识点的战果（4 只都打完后显示） ----------
class _LessonResult extends StatelessWidget {
  const _LessonResult({required this.c, required this.l});
  final HuntController c;
  final LessonState l;

  @override
  Widget build(BuildContext context) {
    final s = l.score();
    final last = c.session.kpIndex + 1 >= c.session.queue.length;
    return Panel(
      title: tr('戰果', 'Result', 'Resultado'),
      color: s.passed ? Px.grassLight : Px.sunLight,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
       Row(children: [
        Turtles(size: 80, mood: s.passed ? TurtleMood.happy : TurtleMood.oops),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.passed ? tr('修煉成功！', 'Training complete!', '¡Entrenamiento completado!') : tr('修煉完成，還要多練練', 'Done — keep practising', 'Terminado: sigue practicando'), style: pixelText(24, weight: FontWeight.w700)),
            Text(tr('打倒 ${s.right} / ${s.total} 只小怪', 'Defeated ${s.right} / ${s.total} monsters', 'Has vencido a ${s.right} / ${s.total} monstruos'), style: pixelText(18)),
            if (!s.passed) Text(tr('沒關係，講解和例題隨時可以回來看。', 'No worries — the lesson and example are always here.', 'No pasa nada: la lección y el ejemplo siempre están aquí.'), style: pixelText(14, color: Px.shadow)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          c.session.isVillage
              ? PxButton(tr('回到地圖', 'Back to map', 'Volver al mapa'), big: true, icon: NesIcons.home, onPressed: () => Navigator.of(context).pop())
              : PxButton(last ? tr('去打 Boss！', 'Fight the Boss!', '¡A por el Jefe!') : tr('下一個知識點', 'Next topic', 'Siguiente tema'), big: true, icon: last ? NesIcons.sword : null, onPressed: c.nextKp),
          const SizedBox(height: 8),
          PxButton(tr('再打一遍（第 ${l.round + 1} 遍）', 'Fight again (round ${l.round + 1})', 'Luchar otra vez (ronda ${l.round + 1})'), type: NesButtonType.normal, onPressed: c.retryLesson),
        ]),
       ]),
        const SizedBox(height: 12),
        HuntTreasure(c: c),
      ]),
    );
  }
}
