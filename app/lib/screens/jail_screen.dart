import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../ai/ai_picker.dart';
import '../ai/ai_service.dart';
import '../game/monster.dart';
import '../game/monster_art.dart';
import '../i18n.dart';
import '../logic/coach_controller.dart';
import '../models/jail.dart';
import '../models/knowledge.dart';
import '../services/local_db.dart';
import '../services/settings.dart';
import '../theme/pixel_theme.dart';
import '../widgets/coach_panel.dart';
import '../widgets/common.dart';
import '../widgets/turtles.dart';
import '../widgets/math_text.dart';
import '../widgets/monsters.dart';
import '../widgets/sprite.dart';
import 'hunt/lesson_view.dart' show AnswerField;

/// 这道题的怪兽：错题原题是那只错题怪兽，小怪按难度
Widget jailMonster(JailCase c, {double size = 64}) {
  final traits = MonsterTraits.fromJson(c.monster);
  final art = traits != null ? MonsterAvatar(traits, size: size) : MonsterSprite(practiceMonster(c.level ?? '提高'), size: size);
  return c.freed ? art : JailBars(size: size, child: art);
}

String jailName(JailCase c) {
  final traits = MonsterTraits.fromJson(c.monster);
  if (traits != null) return traits.displayName;
  return tr('小怪 · ${practiceMonster(c.level ?? '提高').name}', 'Minion · ${practiceMonster(c.level ?? '提高').name}', 'Secuaz · ${practiceMonster(c.level ?? '提高').name}');
}

/// 今天能不能提审（算数）
bool canRetryToday(JailCase c) => c.coachDone && c.winCountsOn(DateTime.now().millisecondsSinceEpoch);

/// 关着的怪兽：前面挡一排铁栏杆
class JailBars extends StatelessWidget {
  const JailBars({super.key, required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final w = (size / 24).clamp(2.0, 6.0).roundToDouble();
    return SizedBox.square(
      dimension: size,
      child: Stack(children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (var i = 0; i < 4; i++) Container(width: w, color: Px.ink)]),
        ),
        Positioned(left: 0, right: 0, top: size * 0.12, child: Container(height: w, color: Px.ink)),
        Positioned(left: 0, right: 0, bottom: size * 0.12, child: Container(height: w, color: Px.ink)),
      ]),
    );
  }
}

/// 怪兽监狱：Benny 放弃过的题都关在这里。一步一步学会以后，要在不同的两天里自己独立做对才放出来。
class JailScreen extends StatefulWidget {
  const JailScreen({super.key, required this.settings, required this.kb});
  final AppSettings settings;
  final Knowledge kb;

  @override
  State<JailScreen> createState() => _JailScreenState();
}

class _JailScreenState extends State<JailScreen> {
  List<JailCase>? _cases;
  String? _error;
  String _filter = 'locked';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await LocalDb.instance.listJail();
      list.sort((a, b) => b.since.compareTo(a.since));
      if (mounted) setState(() => _cases = list);
    } catch (e) {
      if (mounted) setState(() => _error = tr('讀不出存檔（$e）', "Couldn't read the saves ($e)", 'No se pudieron leer las partidas guardadas ($e)'));
    }
  }

  Future<void> _open(JailCase c) async {
    final ai = await pickAi(widget.kb);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JailCaseScreen(jailCase: c.copy(), settings: widget.settings, ai: ai)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final all = _cases;
    final locked = all?.where((c) => !c.freed).toList() ?? [];
    final freed = all?.where((c) => c.freed).toList() ?? [];
    final today = locked.where(canRetryToday).length;
    final shown = _filter == 'freed' ? freed : locked;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: pagePadding(context), children: [
            Row(children: [
              PxButton(tr('← 地圖', '← Map', '← Mapa'), type: NesButtonType.normal, onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 16),
              Expanded(child: Text(tr('怪獸監獄', 'Monster Jail', 'Cárcel de Monstruos'), style: pixelText(isNarrow(context) ? 22 : 28, weight: FontWeight.w700))),
            ]),
            const SizedBox(height: 16),
            PixelBox(
              color: Px.paperDim,
              padding: const EdgeInsets.all(14),
              child: LeadRow(gap: 12, lead: [const Sprite('monster_jail', width: 96, height: 96), const Turtles(size: 64)], child: Text(
                    all == null
                        ? tr('小加和小減在查房…', 'Plus and Minus are checking the cells…', 'Más y Menos están revisando las celdas…')
                        : tr(
                            '你放棄過的題都關在這裡，重點看管。每隻怪獸先一步一步學會；然後過一天再來"提審"：不看步驟，自己完整做一遍。在不同的兩天裡都做對，它就被放出來。\n現在關著 ${locked.length} 只，今天可以提審 $today 只。',
                            'Every problem you gave up on is locked up here. First learn each one step by step. Then come back another day for a "retrial": solve it on your own, no steps. Get it right on two different days and the monster goes free.\n${locked.length} locked up · $today ready for a retrial today.', 'Aquí están encerrados todos los problemas que abandonaste. Primero aprende cada uno paso a paso. Luego vuelve otro día para el «juicio»: resuélvelo tú solo, sin pasos. Si lo aciertas en dos días distintos, el monstruo queda libre.\n${locked.length} encerrados · $today listos para el juicio de hoy.',
                          ),
                    style: pixelText(17),
                  )),
            ),
            const SizedBox(height: 16),
            if (all != null && all.isNotEmpty)
              Wrap(spacing: 10, runSpacing: 8, children: [
                for (final (key, name) in [('locked', tr('還關著 ${locked.length}', 'Locked up ${locked.length}', 'Encerrados ${locked.length}')), ('freed', tr('放出來了 ${freed.length}', 'Set free ${freed.length}', 'Liberados ${freed.length}'))])
                  PxButton(name, type: _filter == key ? NesButtonType.primary : NesButtonType.normal, onPressed: () => setState(() => _filter = key)),
              ]),
            const SizedBox(height: 16),
            if (_error != null) Text(_error!, style: pixelText(15, color: Px.brick)),
            if (all == null && _error == null) const Center(child: NesHourglassLoadingIndicator()),
            if (all != null && shown.isEmpty)
              Text(
                _filter == 'freed'
                    ? tr('還沒有放出來的怪獸。', 'No monsters set free yet.', 'Todavía no has liberado ningún monstruo.')
                    : tr('監獄是空的！放棄過的題會關到這裡來。', 'The jail is empty! Problems you give up on get locked up here.', '¡La cárcel está vacía! Los problemas que abandones quedan encerrados aquí.'),
                style: pixelText(16, color: Px.shadow),
              ),
            Wrap(spacing: 14, runSpacing: 14, children: [for (final c in shown) _JailCard(c: c, onTap: () => _open(c))]),
          ]),
        ),
      ),
    );
  }
}

/// 牢房卡片：哪只怪兽、什么题、刑期还剩多少
class _JailCard extends StatelessWidget {
  const _JailCard({required this.c, required this.onTap});
  final JailCase c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when = DateTime.fromMillisecondsSinceEpoch(c.since);
    final (status, color) = c.freed
        ? (tr('放出來了', 'Set free', 'Liberado'), Px.okText)
        : !c.coachDone
            ? (c.hasSteps ? tr('一步一步來：第 ${c.at + 1} / ${c.steps.length} 步', 'Step by step: ${c.at + 1} / ${c.steps.length}', 'Paso a paso: ${c.at + 1} / ${c.steps.length}') : tr('還沒一步一步學', 'Not learned yet', 'Aún sin aprender'), Px.amber)
            : canRetryToday(c)
                ? (tr('今天可以提審 · 做對 ${c.wins.length}/${JailCase.winsNeeded}', 'Retrial today · ${c.wins.length}/${JailCase.winsNeeded} right', 'Juicio hoy · ${c.wins.length}/${JailCase.winsNeeded} aciertos'), Px.sky)
                : (tr('明天再來提審 · 做對 ${c.wins.length}/${JailCase.winsNeeded}', 'Retrial tomorrow · ${c.wins.length}/${JailCase.winsNeeded} right', 'Juicio mañana · ${c.wins.length}/${JailCase.winsNeeded} aciertos'), Px.shadow);
    return GestureDetector(
      onTap: onTap,
      child: PixelBox(
        width: 300,
        height: 200,
        color: c.freed ? Px.grassLight : Px.panel,
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            jailMonster(c, size: 56),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(jailName(c), maxLines: 2, overflow: TextOverflow.ellipsis, style: pixelText(15, weight: FontWeight.w700)),
                Text(tr('${when.month}月${when.day}日關進來', 'Locked up ${when.month}/${when.day}', 'Encerrado el ${when.day}/${when.month}'), style: pixelText(13, color: Px.shadow)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Expanded(child: ClipRect(child: MathText(c.problem, style: pixelText(14)))),
          Text(status, style: pixelText(14, color: color, weight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// 一间牢房：没学会就一步一步来；学会了就提审（自己独立做一遍，App 比对答案或拍照让 GPT 看）
class JailCaseScreen extends StatefulWidget {
  const JailCaseScreen({super.key, required this.jailCase, required this.settings, required this.ai});
  final JailCase jailCase;
  final AppSettings settings;
  final AiService? ai; // 没登录 ChatGPT 时为空

  @override
  State<JailCaseScreen> createState() => _JailCaseScreenState();
}

class _JailCaseScreenState extends State<JailCaseScreen> {
  late final CoachController k = CoachController(
    c: widget.jailCase,
    ai: widget.ai,
    save: (c) => LocalDb.instance.saveJail(c).catchError((_) {}),
  );
  final _answer = TextEditingController();
  bool _review = false; // 放出来以后回看步骤

  @override
  void dispose() {
    k.dispose();
    _answer.dispose();
    super.dispose();
  }

  void _insert(String s) {
    final sel = _answer.selection;
    final text = _answer.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _answer.value = TextEditingValue(text: text.replaceRange(start, end, s), selection: TextSelection.collapsed(offset: start + s.length));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: k,
        builder: (context, _) {
          final c = k.c;
          return Scaffold(
            body: SafeArea(
              child: ListView(padding: pagePadding(context), children: [
                Row(children: [
                  PxButton(tr('← 監獄', '← Jail', '← Cárcel'), type: NesButtonType.normal, onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 16),
                  Expanded(child: Text(c.freed ? tr('放出來了！', 'Set free!', '¡Liberado!') : tr('牢房', 'Cell', 'Celda'), style: pixelText(26, weight: FontWeight.w700))),
                ]),
                const SizedBox(height: 16),
                Panel(
                  color: c.freed ? Px.grassLight : Px.paperDim,
                  child: LeadRow(gap: 18, lead: [jailMonster(c, size: 120)], child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(jailName(c), style: pixelText(22, weight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(_headline(c), style: pixelText(16, color: Px.shadow)),
                      ])),
                ),
                const SizedBox(height: 18),
                Panel(
                  title: tr('題目', 'Problem', 'Problema'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    MathText(c.problem, style: pixelText(21)),
                    for (final (i, o) in c.options.indexed) ...[const SizedBox(height: 6), MathText('${'ABCD'[i]}. $o', style: pixelText(18))],
                  ]),
                ),
                const SizedBox(height: 18),
                // 提审没做对：说一声，然后重新一步一步来
                if (k.retrial != null && k.retrial!['ok'] != true && !c.coachDone) ...[_RetrialResult(r: k.retrial!, c: c), const SizedBox(height: 14)],
                if (!c.coachDone || _review)
                  CoachPanel(k: k)
                else if (c.freed)
                  Align(alignment: Alignment.centerLeft, child: PxButton(tr('回看步驟', 'Review the steps', 'Repasar los pasos'), type: NesButtonType.normal, onPressed: () => setState(() => _review = true)))
                else
                  _retrial(c),
              ]),
            ),
          );
        },
      );

  String _headline(JailCase c) {
    if (c.freed) return tr('在不同的兩天裡都自己做對了，這隻怪獸刑滿釋放！', 'Solved on your own on two different days — this monster is free!', 'Lo resolviste tú solo en dos días distintos: ¡este monstruo es libre!');
    if (!c.coachDone) return tr('先一步一步把這道題學會。每一步你先自己做，拍照給小加和小減檢查。', 'First learn this problem step by step. Try each step yourself and snap a photo for Plus and Minus.', 'Primero aprende este problema paso a paso. Intenta cada paso tú solo y hazle una foto para Más y Menos.');
    return tr('刑期：在不同的兩天裡自己獨立做對。已經做對 ${c.wins.length} / ${JailCase.winsNeeded} 次。',
        'Sentence: solve it on your own on two different days. Done ${c.wins.length} / ${JailCase.winsNeeded}.', 'Condena: resuélvelo tú solo en dos días distintos. Llevas ${c.wins.length} / ${JailCase.winsNeeded}.');
  }

  /// 提审：不看步骤，自己在纸上完整做一遍
  Widget _retrial(JailCase c) {
    final r = k.retrial;
    final countsToday = c.winCountsOn(DateTime.now().millisecondsSinceEpoch);
    final open = r == null || (r['ok'] != true && r['final'] != true);
    final choice = c.answerType == '选择';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TurtlesSay(
        countsToday
            ? tr('提審開始！不看步驟，自己在紙上把這道題完整做一遍，${c.checkable ? '然後輸入最後的答案。' : '然後拍照給我們看。'}',
                "Retrial time! No steps this time — solve the whole problem on paper yourself, ${c.checkable ? 'then type the final answer.' : 'then snap a photo for us.'}", '¡Hora del juicio! Esta vez sin pasos: resuelve tú solo todo el problema en papel, ${c.checkable ? 'y luego escribe la respuesta final.' : 'y luego haznos una foto.'}')
            : tr('今天已經提審過（或者今天剛關進來），今天做對不算刑期。想練的話照樣可以做，明天再來才算數。',
                "You've already had today's retrial (or it was locked up today), so today won't count. You can still practise — come back tomorrow for it to count.", 'Ya tuviste el juicio de hoy (o lo encerraron hoy), así que hoy no cuenta. Puedes practicar igual; vuelve mañana para que cuente.'),
        mood: TurtleMood.thinking,
        size: 64,
      ),
      const SizedBox(height: 14),
      if (k.error != null) ...[CoachError(k: k), const SizedBox(height: 12)],
      if (k.busy != null) ...[CoachBusy(k: k), const SizedBox(height: 12)],
      if (r != null) ...[_RetrialResult(r: r, c: c), const SizedBox(height: 14)],
      if (open) ...[
        if (c.checkable && choice)
          Wrap(spacing: 12, runSpacing: 10, children: [
            for (var i = 0; i < c.options.length && i < 4; i++) PxButton('ABCD'[i], big: true, onPressed: () => k.submitRetrial('ABCD'[i])),
          ])
        else if (c.checkable) ...[
          AnswerField(controller: _answer, onSubmit: k.submitRetrial, onKey: _insert),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: PxButton(tr('出招（提交）', 'Attack! (submit)', '¡Ataque! (enviar)'), big: true, icon: NesIcons.sword, onPressed: () => k.submitRetrial(_answer.text))),
        ] else ...[
          PhotoPages(
            photos: k.photos,
            title: tr('我的解答', 'My working', 'Mi resolución'),
            hint: tr('把整道題的過程寫清楚，按順序拍下來。', 'Write out the whole solution clearly and snap it in order.', 'Escribe toda la resolución con claridad y hazle fotos en orden.'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: PxButton(tr('讓小加和小減看看', 'Show Plus and Minus', 'Enseñárselo a Más y Menos'), big: true, icon: NesIcons.magnifier, onPressed: k.photos.items.isNotEmpty && k.busy == null ? k.submitRetrialPhoto : null),
          ),
        ],
        const SizedBox(height: 14),
      ],
      Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 10, children: [
        if (r != null && r['ok'] == true && !c.freed) PxButton(tr('回監獄', 'Back to the jail', 'Volver a la cárcel'), big: true, onPressed: () => Navigator.of(context).pop()),
        if (open)
          PxButton(tr('我還是不會，再一步一步來', "I still can't — step by step again", 'Todavía no me sale: otra vez paso a paso'), type: NesButtonType.normal, onPressed: () {
            _answer.clear();
            k.gaveUpAgain();
          }),
      ]),
    ]);
  }
}

/// 提审的结果
class _RetrialResult extends StatelessWidget {
  const _RetrialResult({required this.r, required this.c});
  final Map<String, dynamic> r;
  final JailCase c;

  @override
  Widget build(BuildContext context) {
    final comment = '${r['comment'] ?? ''}';
    if (r['unclear'] == true) {
      return Panel(color: Px.sunLight, child: Verdict(Mark.warn, '${tr('照片看不清：', "The photo isn't clear: ", 'La foto no se ve bien: ')}$comment'));
    }
    if (r['ok'] == true) {
      final (text, mood) = c.freed
          ? (tr('做對了！在不同的兩天裡都做對，這隻怪獸刑滿釋放，你是真的學會了！', "Correct! Right on two different days — the monster is free and you've truly got it!", '¡Correcto! Acertado en dos días distintos: ¡el monstruo es libre y ya lo dominas de verdad!'), TurtleMood.happy)
          : r['counted'] == true
              ? (tr('做對了！刑期 ${c.wins.length} / ${JailCase.winsNeeded}。改天再來做對一次，它就被放出來。', 'Correct! ${c.wins.length} / ${JailCase.winsNeeded} done. Get it right once more on another day to set it free.', '¡Correcto! Llevas ${c.wins.length} / ${JailCase.winsNeeded}. Acierta una vez más otro día para liberarlo.'), TurtleMood.happy)
              : (tr('做對了！不過今天不算刑期（要在不同的兩天裡做對），明天再來。', "Correct! But today doesn't count (it has to be two different days) — come back tomorrow.", '¡Correcto! Pero hoy no cuenta (tienen que ser dos días distintos): vuelve mañana.'), TurtleMood.idle);
      return Panel(
        color: Px.grassLight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TurtlesSay(text, mood: mood, size: 64),
          if (comment.isNotEmpty) ...[const SizedBox(height: 8), MathText(comment, style: pixelText(15))],
        ]),
      );
    }
    return Panel(
      color: Px.brickLight,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Verdict(
          Mark.bad,
          r['final'] == true
              ? tr('還是沒做對${'${r['last'] ?? ''}'.isEmpty ? '' : '（你的答案：${r['last']}）'}。沒關係，下面再一步一步來一遍，刑期從頭算。',
                  "Still not right${'${r['last'] ?? ''}'.isEmpty ? '' : ' (your answer: ${r['last']})'}. No worries — let's go step by step again below. The sentence starts over.", 'Todavía no está bien${'${r['last'] ?? ''}'.isEmpty ? '' : ' (tu respuesta: ${r['last']})'}. No pasa nada: vamos otra vez paso a paso aquí abajo. La condena vuelve a empezar.')
              : tr('${r['last']} 不對，再檢查一遍，還有一次機會。', '${r['last']} is not right. Check again — one more try.', '${r['last']} no es correcto. Revísalo: te queda un intento.'),
        ),
        if (comment.isNotEmpty) ...[const SizedBox(height: 6), MathText(comment, style: pixelText(15))],
      ]),
    );
  }
}
