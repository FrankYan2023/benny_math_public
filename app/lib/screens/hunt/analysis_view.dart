import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../../game/game_data.dart';
import '../../game/monster_art.dart';
import '../../i18n.dart';
import '../../logic/hunt_controller.dart';
import '../../theme/pixel_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/math_text.dart';
import '../../widgets/turtles.dart';
import 'hunt_screen.dart';

/// 怪兽图鉴：这道题是什么怪兽、错在哪、弱点（要修炼的知识点）
class AnalysisView extends StatelessWidget {
  const AnalysisView({super.key, required this.c});
  final HuntController c;

  @override
  Widget build(BuildContext context) {
    final a = c.session.analysis!;
    if (a['readable'] != true) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TurtlesSay('${tr('照片看不清：', "The photo isn't clear: ", 'La foto no se ve bien: ')}${a['unreadable_reason'] ?? tr('換個角度再拍一次吧。', 'try again from another angle.', 'inténtalo desde otro ángulo.')}', mood: TurtleMood.oops),
        gap,
        Align(alignment: Alignment.centerRight, child: PxButton(tr('重新拍照', 'Retake photos', 'Repetir fotos'), big: true, icon: NesIcons.camera, onPressed: c.retakePhotos)),
      ]);
    }

    final err = (a['error'] as Map).cast<String, dynamic>();
    final correct = a['is_correct'] == true;
    final missing = (a['missing_kps'] as List).cast<Map>();
    final monster = c.session.monsterTraits;
    final g = GameData.instance;
    final noMonster = correct && missing.isEmpty;

    Widget verdict() {
      if (a['has_student_work'] != true) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('還沒寫解答', 'No working yet', 'Aún sin resolución'), style: pixelText(18, color: Px.amber, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          MathText('${err['description']}', style: pixelText(16)),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Verdict(correct ? Mark.ok : Mark.bad, correct
            ? tr('你的答案 ${a['student_answer']} 是對的', 'Your answer ${a['student_answer']} is right', 'Tu respuesta ${a['student_answer']} es correcta')
            : tr('你的答案 ${a['student_answer']} 不對', 'Your answer ${a['student_answer']} is not right', 'Tu respuesta ${a['student_answer']} no es correcta')),
        if (!correct) ...[
          const SizedBox(height: 6),
          Text('${err['step'] != null ? tr('錯在第 ${err['step']} 步', 'Went wrong at step ${err['step']}', 'Falló en el paso ${err['step']}') : tr('問題在這裡', "Here's the problem", 'Este es el problema')} · ${errorLabel('${err['type']}')}', style: pixelText(16, color: Px.brick)),
          const SizedBox(height: 4),
          MathText('${err['description']}', style: pixelText(16)),
        ],
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: LeadRow(gap: 20, lead: [noMonster ? const Turtles(size: 120, mood: TurtleMood.happy) : MonsterAvatar(monster, size: 128)], child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(noMonster ? tr('這道題沒有怪獸！', 'No monster here!', '¡Aquí no hay ningún monstruo!') : monster.displayName, style: pixelText(24, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                if (noMonster)
                  Text(tr('你做對了，小加和小減給你點個贊。', 'You got it right — Plus and Minus give you a thumbs up.', '¡Lo hiciste bien! Más y Menos te dan un pulgar arriba.'), style: pixelText(16, color: Px.shadow))
                else ...[
                  if (monster.intro.isNotEmpty) MathText(monster.intro, style: pixelText(16)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final (k, v) in [
                      (tr('錯因', 'Mistake', 'Error'), errorLabel(c.session.errorType)),
                      (tr('性格', 'Mood', 'Carácter'), g.word(monster.personality)),
                      (tr('外形', 'Look', 'Aspecto'), g.word(monster.look)),
                      (tr('顏色', 'Color', 'Color'), g.word(monster.color)),
                    ])
                      PixelBox(
                        shadow: false,
                        color: Px.paper,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('$k: $v', style: pixelText(13, color: Px.shadow)),
                      ),
                  ]),
                ],
              ])),
        ),
        gap,
        Panel(title: tr('這道題', 'The problem', 'El problema'), child: MathText('${a['problem_text']}', style: pixelText(20))),
        gap,
        Panel(title: tr('你的做法', 'Your working', 'Tu resolución'), child: verdict()),
        gap,
        Panel(
          title: tr('用到的知識點', 'Topics used', 'Temas usados'),
          child: Column(children: [
            for (final k in (a['knowledge_points'] as List).cast<Map>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Judge(k['judgement'] as String),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        KpLabel(c, k['kp_id'] as String),
                        Text(k['role'] == '主' ? tr('主', 'main', 'principal') : tr('輔', 'supporting', 'de apoyo'), style: pixelText(13, color: Px.shadow)),
                      ]),
                      MathText('${k['evidence']}', style: pixelText(14, color: Px.shadow)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
        gap,
        if (missing.isNotEmpty) ...[
          Panel(
            title: tr('怪獸的弱點 = 你要修煉的知識點 · 大約 ${a['estimated_minutes']} 分鐘', "The monster's weak spots = topics to train · about ${a['estimated_minutes']} min", 'Los puntos débiles del monstruo = temas para entrenar · unos ${a['estimated_minutes']} min'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TurtlesSay('${a['plan_summary']}', size: 64),
              const SizedBox(height: 12),
              for (final (i, m) in missing.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Step('${i + 1}'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        KpLabel(c, m['kp_id'] as String),
                        MathText('${m['reason']}', style: pixelText(15, color: Px.shadow)),
                      ]),
                    ),
                    Text(tr('${m['minutes']} 分鐘', '${m['minutes']} min', '${m['minutes']} min'), style: pixelText(14, color: Px.shadow)),
                  ]),
                ),
              Row(children: [
                _Step('${missing.length + 1}', boss: true),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('Boss 戰：重做原題，寫出最後的答案', 'Boss fight: redo the original problem and give the final answer', 'Batalla final: vuelve a hacer el problema original y da la respuesta final'), style: pixelText(17, weight: FontWeight.w700))),
              ]),
            ]),
          ),
          gap,
        ],
        if (missing.isNotEmpty) ...[
          Align(alignment: Alignment.centerRight, child: _TrainingStatus(c: c)),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: missing.isNotEmpty
              ? PxButton('${tr('開始修煉：', 'Start training: ', 'Empezar a entrenar: ')}${c.kpName(missing.first['kp_id'] as String)}', big: true, icon: NesIcons.sword, onPressed: c.startLearning)
              : correct
                  ? PxButton(tr('看看標準解法', 'See the model solution', 'Ver la solución modelo'), big: true, icon: NesIcons.trophy, onPressed: c.finish)
                  : PxButton(tr('不用修煉，直接 Boss 戰（細心重算）', 'No training needed — straight to the Boss (redo carefully)', 'No hace falta entrenar: directo al Jefe (rehazlo con cuidado)'), big: true, icon: NesIcons.sword, onPressed: c.goToBoss),
        ),
      ],
    );
  }
}

/// 修炼内容是在后台生成的：显示准备好了没有
class _TrainingStatus extends StatelessWidget {
  const _TrainingStatus({required this.c});
  final HuntController c;

  @override
  Widget build(BuildContext context) {
    if (c.session.trainingReady) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const MarkIcon(Mark.ok, size: 18),
        const SizedBox(width: 8),
        Text(tr('修煉內容準備好了', 'Training is ready', 'El entrenamiento está listo'), style: pixelText(15, color: Px.okText)),
      ]);
    }
    if (c.trainingError != null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${tr('修煉內容沒準備好：', "Training isn't ready: ", 'El entrenamiento no está listo: ')}${c.trainingError}', style: pixelText(14, color: Px.brick)),
        const SizedBox(width: 10),
        PxButton(tr('重試', 'Retry', 'Reintentar'), type: NesButtonType.normal, onPressed: c.waitForTraining),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 18, height: 18, child: NesHourglassLoadingIndicator()),
      const SizedBox(width: 10),
      Text(tr('小加和小減正在後臺準備修煉內容，你先看看圖鑑…', 'Plus and Minus are preparing your training — read the guide meanwhile…', 'Más y Menos están preparando tu entrenamiento; mientras, lee la guía…'), style: pixelText(14, color: Px.shadow)),
    ]);
  }
}

class _Judge extends StatelessWidget {
  const _Judge(this.judgement);
  final String judgement;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (judgement) {
      '会' => (Px.grass, NesIcons.check),
      '不会' => (Px.brick, NesIcons.close),
      _ => (Px.sun, NesIcons.questionMark),
    };
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: color, border: Border.all(color: Px.ink, width: 2)),
      alignment: Alignment.center,
      child: NesIcon(iconData: icon, size: const Size.square(18), primaryColor: color == Px.sun ? Px.ink : Colors.white),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, {this.boss = false});
  final String n;
  final bool boss;

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: boss ? Px.brick : Px.paper, border: Border.all(color: boss ? Px.ink : Px.sky, width: 3)),
        alignment: Alignment.center,
        child: Text(n, style: pixelText(15, weight: FontWeight.w700, color: boss ? Colors.white : Px.sky)),
      );
}
