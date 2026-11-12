import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../../game/monster_art.dart';
import '../../i18n.dart';
import '../../logic/hunt_controller.dart';
import '../../theme/pixel_theme.dart';
import '../../widgets/coach_panel.dart';
import '../../widgets/common.dart';
import '../../widgets/math_text.dart';
import 'hunt_screen.dart';
import 'lesson_view.dart' show AnswerField;

/// Boss 战：在纸上重做原题（订正）。两种打法：
///   输入最后的答案 —— App 自己比对，不调用 GPT
///   拍照订正 —— GPT 连过程一起看，App 再拿最终答案和标准答案比一遍
/// 原题没法自动比对（证明、作图、多问）时，对照标准解法自己判断，或者拍照。
class BossView extends StatefulWidget {
  const BossView({super.key, required this.c});
  final HuntController c;

  @override
  State<BossView> createState() => _BossViewState();
}

class _BossViewState extends State<BossView> {
  late final _answer = TextEditingController(text: widget.c.session.boss.last);
  bool _showSolution = false;
  late bool _photo = widget.c.photoMode;

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
    final s = c.session;
    final a = s.analysis!;
    final r = s.boss;
    final monster = s.monsterTraits;
    final won = s.bossWon;
    final done = s.bossDone;
    final checkable = s.bossCheckable;
    final choice = a['answer_type'] == '选择';
    final rc = s.recheck;
    final coach = c.bossCoach;
    final coachDone = coach?.c.coachDone ?? false;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        child: LeadRow(gap: 20, lead: [MonsterAvatar(monster, size: 140, defeated: won)], child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(won ? tr('${monster.displayName}被打敗了！', '${monster.displayName} is beaten!', '¡${monster.displayName} ha sido vencido!') : 'Boss: ${monster.displayName}',
                  style: pixelText(24, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                won
                    ? tr('訂正成功，剛學的知識點用上了。', 'Corrected! You used what you just learned.', '¡Corregido! Usaste lo que acabas de aprender.')
                    : tr('在紙上把原題完整做一遍，然後輸入最後的答案，或者拍照讓小加和小減連過程一起看。',
                        'Redo the original problem on paper, then type the final answer — or snap a photo so Plus and Minus can check your working too.', 'Vuelve a hacer el problema original en papel y escribe la respuesta final, o haz una foto para que Más y Menos revisen también tu resolución.'),
                style: pixelText(16, color: Px.shadow),
              ),
            ])),
      ),
      gap,
      Panel(title: tr('原題', 'Original problem', 'Problema original'), child: MathText(s.problemText, style: pixelText(21))),
      gap,
      if (!done) ...[
        Row(children: [
          Expanded(
            child: NesButton(
              type: !_photo ? NesButtonType.primary : NesButtonType.normal,
              onPressed: () => setState(() => _photo = false),
              child: Center(child: Text(tr('輸入最後的答案', 'Type the final answer', 'Escribir la respuesta final'), style: pixelText(17, color: !_photo ? Colors.white : Px.ink))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: NesButton(
              type: _photo ? NesButtonType.primary : NesButtonType.normal,
              onPressed: () => setState(() => _photo = true),
              child: Center(child: Text(tr('拍照訂正（看過程）', 'Photo correction (checks working)', 'Corrección con foto (revisa el proceso)'), style: pixelText(17, color: _photo ? Colors.white : Px.ink))),
            ),
          ),
        ]),
        gap,
      ],
      // ---------- 拍照订正 ----------
      if (_photo && !done) ...[
        if (!s.demo)
          PhotoPages(
            photos: c.redoPhotos,
            title: tr('我訂正好的解答', 'My corrected working', 'Mi corrección'),
            hint: tr('只拍你寫的解答就行，不用拍題目（題目用原題）。把每一步寫清楚，寫了好幾張就按順序都拍上。',
                'Just snap your working — no need to include the problem (we use the original). Write every step clearly; several pages? Snap them in order.', 'Solo haz foto de tu resolución: no hace falta el enunciado (usamos el original). Escribe cada paso con claridad; ¿varias hojas? Hazles foto en orden.'),
          ),
        if (rc != null) ...[gap, _RecheckResult(rc: rc)],
        gap,
        Align(
          alignment: Alignment.centerRight,
          child: PxButton(tr('讓小加和小減看看', 'Show Plus and Minus', 'Enseñárselo a Más y Menos'), big: true, icon: NesIcons.magnifier, onPressed: c.canRecheck ? c.submitRecheck : null),
        ),
        gap,
      ],
      // ---------- 输入最后的答案 ----------
      if (!_photo && checkable) ...[
        if (!done) ...[
          AnswerField(controller: _answer, onSubmit: c.submitBoss, onKey: _insert),
          if (choice) Text(tr('選擇題寫選項字母，比如 B。', 'For multiple choice, type the letter, e.g. B.', 'En las preguntas tipo test, escribe la letra, por ejemplo B.'), style: pixelText(14, color: Px.shadow)),
          gap,
        ],
        if (r.tries > 0 || done)
          Panel(
            color: won ? Px.grassLight : (done ? Px.brickLight : null),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (r.override)
                Verdict(Mark.ok, tr('算你對：寫法不同，意思一樣', 'Counted as right: written differently, same meaning', 'Cuenta como correcta: escrita de otra forma, mismo significado'))
              else if (r.correct)
                Verdict(Mark.ok, tr('答對了${r.tries > 1 ? '（第二次）' : ''}！你的答案：${r.last}', 'Correct${r.tries > 1 ? ' (2nd try)' : ''}! Your answer: ${r.last}', '¡Correcto${r.tries > 1 ? ' (2.º intento)' : ''}! Tu respuesta: ${r.last}'))
              else if (!done)
                Verdict(Mark.bad, tr('${r.last} 不對，再檢查一遍，還有一次機會。', '${r.last} is not right. Check again — one more try.', '${r.last} no es correcto. Revísalo: te queda un intento.'))
              else ...[
                if (r.tries > 0) Verdict(Mark.bad, '${tr('你的答案：', 'Your answer: ', 'Tu respuesta: ')}${r.last}'),
                // 不直接给答案：一步一步学会它（下面）
                Text(tr('這次沒打贏。答案先不告訴你，下面一步一步把它學會。', "Not this time. No answer yet — let's learn it step by step below.", 'Esta vez no. Todavía no te damos la respuesta: aprendámoslo paso a paso aquí abajo.'), style: pixelText(16, color: Px.brick)),
              ],
            ]),
          ),
        if (r.tries > 0 || done) gap,
      ] else if (!_photo && !done) ...[
        TurtlesSay(
          tr('這道題小加和小減沒法自動對答案。做完後開啟標準解法對照檢查，或者換成"拍照訂正"。',
              "Plus and Minus can't auto-check this one. When you're done, open the model solution to compare — or switch to photo correction.", 'Más y Menos no pueden comprobar este automáticamente. Cuando termines, abre la solución modelo para comparar, o cambia a corrección con foto.'),
          size: 64,
        ),
        gap,
      ],
      if (done && rc != null && won) ...[_RecheckResult(rc: rc), gap],
      if (done && won) ...[HuntTreasure(c: c, quietIfTaken: true), gap],
      // 打赢了、或者自己对照：看标准解法；放弃了、没打赢：不直接给答案，一步一步来
      if (won || (!checkable && !_photo && _showSolution && !done))
        Panel(
          title: tr('標準解法', 'Model solution', 'Solución modelo'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, st) in (a['solution_steps'] as List).indexed)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: MathText('${i + 1}. $st', style: pixelText(18))),
            MathText('${tr('答案：', 'Answer: ', 'Respuesta: ')}${a['correct_answer']}', style: pixelText(19, weight: FontWeight.w700)),
          ]),
        )
      else if (coach != null && done)
        CoachPanel(
          k: coach,
          doneNote: tr('${monster.displayName}被關進了怪獸監獄。過一天再去監獄裡自己做一遍，在不同的兩天裡都做對，它才會被放出來。',
              'The ${monster.displayName} is now locked in the Monster Jail. Come back another day and solve it on your own — get it right on two different days to set it free.', '${monster.displayName} queda encerrado en la Cárcel de Monstruos. Vuelve otro día y resuélvelo tú solo: si lo aciertas en dos días distintos, quedará libre.'),
        )
      else if (done)
        Align(
          alignment: Alignment.centerLeft,
          child: PxButton(tr('一步一步學會它', 'Learn it step by step', 'Aprenderlo paso a paso'), big: true, onPressed: c.coachBoss),
        )
      else
        Wrap(spacing: 12, runSpacing: 10, children: [
          if (!checkable && !_photo) PxButton(tr('做完了，開啟對照', "I'm done — let me compare", 'Ya he terminado: quiero comparar'), type: NesButtonType.normal, onPressed: () => setState(() => _showSolution = true)),
          PxButton(tr('我放棄，一步一步來', 'I give up — go step by step', 'Me rindo: vamos paso a paso'), type: NesButtonType.warning, onPressed: c.giveUpBoss),
        ]),
      gap,
      if (!checkable && !_photo && _showSolution && !done) ...[
        Text(tr('對照下來，你做對了嗎？', 'After comparing, did you get it right?', 'Después de comparar, ¿te salió bien?'), style: pixelText(20, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 10, children: [
          PxButton(tr('做對了', 'Yes', 'Sí'), icon: NesIcons.check, onPressed: () => c.selfCheckBoss(true)),
          PxButton(tr('還沒做對', 'Not yet', 'Todavía no'), type: NesButtonType.normal, onPressed: () => c.selfCheckBoss(false)),
        ]),
        gap,
      ],
      if (checkable && !_photo && r.revealed && coachDone && !r.override && r.tries > 0 && !choice && a['answer_type'] != '数值') ...[
        Align(alignment: Alignment.centerLeft, child: PxButton(tr('我的寫法不同，其實是對的', "I wrote it differently — it's actually right", 'Lo escribí de otra forma, pero en realidad está bien'), type: NesButtonType.normal, onPressed: c.markBossOverride)),
        gap,
      ],
      Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 10, children: [
        if (s.queue.isNotEmpty) PxButton(tr('回去看修煉', 'Back to training', 'Volver al entrenamiento'), type: NesButtonType.normal, onPressed: c.backToLearning),
        if (!_photo && checkable && !done) PxButton(tr('出招（提交）', 'Attack! (submit)', '¡Ataque! (enviar)'), big: true, icon: NesIcons.sword, onPressed: () => c.submitBoss(_answer.text)),
        if (done) ...[
          PxButton(tr('再打一次 Boss', 'Fight the Boss again', 'Luchar otra vez contra el Jefe'), type: NesButtonType.normal, onPressed: () {
            _answer.clear();
            setState(() => _showSolution = false);
            c.retryBoss();
          }),
          PxButton(won ? tr('收進怪獸屋', 'Send to the Monster House', 'Enviar a la Casa de los Monstruos') : tr('先到這裡', 'Stop here', 'Parar aquí'), big: true, icon: won ? NesIcons.trophy : null, onPressed: c.finish),
        ],
      ]),
    ]);
  }
}

/// 拍照订正的结果：GPT 看到的答案、判定、评语；App 比对不一致时说明
class _RecheckResult extends StatelessWidget {
  const _RecheckResult({required this.rc});
  final Map<String, dynamic> rc;

  @override
  Widget build(BuildContext context) {
    final verdict = '${rc['verdict']}';
    final ok = rc['ok'] == true;
    final (mark, text) = switch (verdict) {
      '看不清' => (Mark.warn, '${tr('照片看不清：', "The photo isn't clear: ", 'La foto no se ve bien: ')}${rc['unreadable_reason'] ?? ''}'),
      '全对' when ok => (Mark.ok, tr('全對！過程也很清楚', 'All correct — clear working too!', '¡Todo correcto, y el proceso muy claro!')),
      '答案对但过程有问题' when ok => (Mark.warn, tr('答案對了，過程還有一點問題', 'Right answer, but the working has a problem', 'Respuesta correcta, pero el proceso tiene un fallo')),
      _ when rc['mismatch'] == true => (
          Mark.bad,
          tr('小加和小減看到你的答案是 ${rc['final_answer_seen']}，和標準答案對不上，再檢查一遍', 'Plus and Minus read your answer as ${rc['final_answer_seen']}, which does not match. Check again', 'Más y Menos leen tu respuesta como ${rc['final_answer_seen']}, y no coincide. Revísalo'),
        ),
      _ => (Mark.bad, tr('還不對', 'Not right yet', 'Todavía no está bien')),
    };
    final step = rc['first_error_step'];
    return Panel(
      color: ok ? Px.grassLight : Px.sunLight,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Verdict(mark, text),
        if (step != null && verdict != '看不清')
          Text(tr('第 $step 步開始有問題 · ${errorLabel('${rc['error_type']}')}', 'Problem starts at step $step · ${errorLabel('${rc['error_type']}')}', 'El fallo empieza en el paso $step · ${errorLabel('${rc['error_type']}')}'), style: pixelText(15, color: Px.brick)),
        if ('${rc['comment'] ?? ''}'.isNotEmpty) ...[const SizedBox(height: 6), MathText('${rc['comment']}', style: pixelText(16))],
        if (!ok && verdict != '看不清') ...[
          const SizedBox(height: 6),
          Text(tr('改好後再拍一次。', 'Fix it and snap again.', 'Corrígelo y vuelve a hacer la foto.'), style: pixelText(14, color: Px.shadow)),
        ],
      ]),
    );
  }
}
