import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../i18n.dart';
import '../logic/report.dart';
import '../models/knowledge.dart';
import '../services/local_db.dart';
import '../theme/pixel_theme.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import 'hunt/hunt_screen.dart' show errorLabel;

/// 家长报表：扫过哪些题、结果如何、哪些知识点没学会、错因分布、学习时长、怪兽监狱。
/// 数据都在这台设备上；语气平实，给家长看。
class ParentReportScreen extends StatefulWidget {
  const ParentReportScreen({super.key, required this.kb, required this.name});
  final Knowledge kb;
  final String name;

  @override
  State<ParentReportScreen> createState() => _ParentReportScreenState();
}

class _ParentReportScreenState extends State<ParentReportScreen> {
  String _range = '7';
  ParentReport? _r;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final to = now.millisecondsSinceEpoch;
    final days = int.tryParse(_range);
    final from = days == null ? 0 : DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1)).millisecondsSinceEpoch;
    final r = await ParentReport.build(LocalDb.instance, widget.kb, from: from, to: to);
    if (mounted) setState(() => _r = r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(title: Text(tr('${widget.name}的學習報表', "${widget.name}'s report", 'Informe de ${widget.name}'), style: pixelText(20)), backgroundColor: Px.paper),
      body: SafeArea(
        child: r == null
            ? const Center(child: NesHourglassLoadingIndicator())
            : ListView(padding: EdgeInsets.all(narrow ? 14 : 24), children: [
                Wrap(spacing: 10, runSpacing: 8, children: [
                  for (final (k, name) in [('7', tr('近 7 天', 'Last 7 days', 'Últimos 7 días')), ('30', tr('近 30 天', 'Last 30 days', 'Últimos 30 días')), ('90', tr('近 90 天', 'Last 90 days', 'Últimos 90 días')), ('all', tr('全部', 'All', 'Todo'))])
                    PxButton(name, type: _range == k ? NesButtonType.primary : NesButtonType.normal, onPressed: () {
                      setState(() => _range = k);
                      _load();
                    }),
                ]),
                const SizedBox(height: 16),
                _Summary(r.summary),
                const SizedBox(height: 16),
                _Attention(r, widget.kb),
                const SizedBox(height: 16),
                _Problems(r, widget.kb),
                const SizedBox(height: 16),
                _Jail(r, widget.kb),
                const SizedBox(height: 16),
                _Errors(r),
                const SizedBox(height: 16),
                _KnowledgeMap(r, widget.kb),
                const SizedBox(height: 16),
                Text(
                  tr('知識點狀態按固定規則計算：分析時判為不會、或者練習沒過關 → 薄弱；練習過關 → 學習中；重做原題用對 → 基本掌握。資料只存在這臺裝置上。',
                      'Topic status follows fixed rules: marked as not known or practice not passed → weak; practice passed → learning; used correctly when redoing the problem → got it. All data stays on this device.', 'El estado de los temas sigue reglas fijas: marcado como no sabido o práctica no superada → débil; práctica superada → aprendiendo; usado bien al rehacer el problema → lo tiene. Todos los datos se quedan en este dispositivo.'),
                  style: pixelText(13, color: Px.shadow),
                ),
              ]),
      ),
    );
  }
}

String _date(int at) {
  final d = DateTime.fromMillisecondsSinceEpoch(at);
  return tr('${d.month}月${d.day}日', '${d.month}/${d.day}', '${d.day}/${d.month}');
}

/// 小标签
class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => PixelBox(
        color: color,
        border: color,
        shadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(text, style: pixelText(13, color: Colors.white)),
      );
}

class _Summary extends StatelessWidget {
  const _Summary(this.s);
  final ReportSummary s;

  @override
  Widget build(BuildContext context) {
    String pct(int a, int b) => b == 0 ? '—' : '${(a * 100 / b).round()}%';
    final tiles = [
      (tr('掃了幾道題', 'Problems scanned', 'Problemas escaneados'), '${s.problems}'),
      (tr('首次就做對', 'Right the first time', 'Bien a la primera'), '${s.firstTryCorrect}'),
      (tr('重做原題做對', 'Redo correct', 'Repeticiones correctas'), '${s.redoCorrect} / ${s.redoTotal}'),
      (tr('練習正確率', 'Practice accuracy', 'Aciertos en la práctica'), pct(s.practiceRight, s.practiceTotal)),
      (tr('知識點過關', 'Topics passed', 'Temas superados'), '${s.lessonsPassed} / ${s.lessonsTotal}'),
      (tr('學習時長', 'Time spent', 'Tiempo dedicado'), tr('${s.minutes} 分鐘 · ${s.activeDays} 天', '${s.minutes} min · ${s.activeDays} days', '${s.minutes} min · ${s.activeDays} días')),
    ];
    return Panel(
      title: tr('總覽', 'Overview', 'Resumen'),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (label, value) in tiles)
          PixelBox(
            width: 150,
            color: Px.paper,
            shadow: false,
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: pixelText(13, color: Px.shadow)),
              Text(value, style: pixelText(20, weight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}

class _Attention extends StatelessWidget {
  const _Attention(this.r, this.kb);
  final ParentReport r;
  final Knowledge kb;

  @override
  Widget build(BuildContext context) => Panel(
        title: tr('需要關注的知識點', 'Topics that need attention', 'Temas que necesitan atención'),
        child: r.attention.isEmpty
            ? Text(tr('目前沒有薄弱的知識點。', 'No weak topics right now.', 'Ahora mismo no hay temas débiles.'), style: pixelText(15, color: Px.shadow))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final a in r.attention)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(kb.byId[a.id]?.label ?? a.id, style: pixelText(16, weight: FontWeight.w700)),
                          if (a.lastErrorType != null)
                            Text('${tr('最近的錯因：', 'Latest mistake: ', 'Último error: ')}${errorLabel(a.lastErrorType!)}', style: pixelText(13, color: Px.shadow)),
                        ]),
                      ),
                      Text(tr('錯過 ${a.wrongCount} 次', 'Missed ${a.wrongCount}×', 'Fallado ${a.wrongCount} veces'), style: pixelText(14, color: Px.brick)),
                    ]),
                  ),
              ]),
      );
}

class _Problems extends StatelessWidget {
  const _Problems(this.r, this.kb);
  final ParentReport r;
  final Knowledge kb;

  static String resultLabel(String v) => switch (v) {
        '做对了' => tr('做對了', 'Right', 'Bien'),
        '做错了' => tr('做錯了', 'Wrong', 'Mal'),
        '不会做' => tr('不會做', "Couldn't do it", 'No sabía'),
        '没写解答' => tr('沒寫解答', 'No working', 'Sin resolución'),
        '还不对' => tr('還不對', 'Not yet', 'Aún no'),
        '没重做' => tr('沒重做', 'Not redone', 'Sin repetir'),
        _ => v,
      };
  static Color resultColor(String v) => switch (v) {
        '做对了' => Px.grass,
        '没重做' || '没写解答' => Px.stone,
        _ => Px.brick,
      };

  @override
  Widget build(BuildContext context) => Panel(
        title: tr('掃過的題目', 'Problems scanned', 'Problemas escaneados'),
        child: r.problems.isEmpty
            ? Text(tr('這段時間還沒有掃題記錄。', 'No problems scanned in this period.', 'No hay problemas escaneados en este periodo.'), style: pixelText(15, color: Px.shadow))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final p in r.problems)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(_date(p.at), style: pixelText(13, color: Px.shadow)),
                        Text(tr('首次：', 'First try:', 'A la primera:'), style: pixelText(13)),
                        _Pill(resultLabel(p.firstResult), resultColor(p.firstResult)),
                        if (p.errorType != '无错误') _Pill(errorLabel(p.errorType), Px.amber),
                        if (p.redo != '不用重做') ...[Text(tr('重做原題：', 'Redo:', 'Repetición:'), style: pixelText(13)), _Pill(resultLabel(p.redo), resultColor(p.redo))],
                      ]),
                      const SizedBox(height: 4),
                      MathText(p.problemText, style: pixelText(15)),
                      if (p.firstResult == '做错了' && p.errorDescription.isNotEmpty)
                        MathText(p.errorDescription, style: pixelText(13, color: Px.shadow)),
                      if (p.missingKps.isNotEmpty)
                        Text(
                          '${tr('要補的知識點：', 'Topics to learn: ', 'Temas que aprender: ')}${[
                            for (final id in p.missingKps)
                              '${kb.byId[id]?.label ?? id}（${p.lessons[id] == null ? tr('還沒學', 'not started', 'sin empezar') : '${p.lessons[id]!.passed ? tr('過關', 'passed', 'superado') : tr('沒過關', 'not passed', 'no superado')} ${p.lessons[id]!.right}/${p.lessons[id]!.total}'}）',
                          ].join(tr('、', ', ', ', '))}',
                          style: pixelText(13),
                        ),
                    ]),
                  ),
              ]),
      );
}

class _Jail extends StatelessWidget {
  const _Jail(this.r, this.kb);
  final ParentReport r;
  final Knowledge kb;

  @override
  Widget build(BuildContext context) => Panel(
        title: tr('怪獸監獄（放棄過的題）', 'Monster Jail (problems given up on)', 'Cárcel de Monstruos (problemas abandonados)'),
        child: r.jail.isEmpty
            ? Text(tr('還沒有放棄過的題。', 'No problems given up on yet.', 'Todavía no hay problemas abandonados.'), style: pixelText(15, color: Px.shadow))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  tr('放棄、或者答錯兩次的題，App 會一步一步帶著做（每一步先自己做、拍照檢查），然後關進怪獸監獄，要在不同的兩天裡自己獨立做對才放出來。現在關著 ${r.jailLocked} 道，已放出 ${r.jailFreed} 道。',
                      'Problems given up on (or missed twice) are worked through step by step (each step done alone and checked by photo), then locked in the Monster Jail until solved independently on two different days. Locked: ${r.jailLocked}. Freed: ${r.jailFreed}.', 'Los problemas abandonados (o fallados dos veces) se trabajan paso a paso (cada paso se hace solo y se revisa con una foto) y luego se encierran en la Cárcel de Monstruos hasta resolverlos sin ayuda en dos días distintos. Encerrados: ${r.jailLocked}. Liberados: ${r.jailFreed}.'),
                  style: pixelText(13, color: Px.shadow),
                ),
                for (final j in r.jail)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(tr('${_date((j['since'] as num).toInt())} 關進來', 'Locked ${_date((j['since'] as num).toInt())}', 'Encerrado el ${_date((j['since'] as num).toInt())}'), style: pixelText(13, color: Px.shadow)),
                        if (j['freedAt'] != null)
                          _Pill(tr('已放出', 'Freed', 'Liberado'), Px.grass)
                        else ...[
                          _Pill(tr('還關著', 'Locked', 'Encerrado'), Px.brick),
                          Text(tr('獨立做對 ${(j['wins'] as List?)?.length ?? 0}/2 次', 'Solved alone ${(j['wins'] as List?)?.length ?? 0}/2', 'Resuelto sin ayuda ${(j['wins'] as List?)?.length ?? 0}/2'), style: pixelText(13)),
                        ],
                        if (((j['stepsTotal'] as num?) ?? 0) > 0)
                          Text(tr('分步：自己做對 ${j['stepsDone']} / ${j['stepsTotal']} 步', 'Steps done alone: ${j['stepsDone']} / ${j['stepsTotal']}', 'Pasos hechos sin ayuda: ${j['stepsDone']} / ${j['stepsTotal']}'), style: pixelText(13)),
                      ]),
                      const SizedBox(height: 4),
                      MathText('${j['problemText'] ?? ''}', style: pixelText(15)),
                    ]),
                  ),
              ]),
      );
}

class _Errors extends StatelessWidget {
  const _Errors(this.r);
  final ParentReport r;

  @override
  Widget build(BuildContext context) {
    final most = r.errorTypes.fold(1, (m, e) => e.$2 > m ? e.$2 : m);
    return Panel(
      title: tr('錯因分佈', 'Kinds of mistakes', 'Tipos de errores'),
      child: r.errorTypes.isEmpty
          ? Text(tr('沒有錯題記錄。', 'No mistakes recorded.', 'No hay errores registrados.'), style: pixelText(15, color: Px.shadow))
          : Column(children: [
              for (final (type, n) in r.errorTypes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 150, child: Text(errorLabel(type), style: pixelText(14))),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(widthFactor: n / most, child: Container(height: 14, color: Px.sky)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('$n', style: pixelText(14, weight: FontWeight.w700)),
                  ]),
                ),
            ]),
    );
  }
}

class _KnowledgeMap extends StatelessWidget {
  const _KnowledgeMap(this.r, this.kb);
  final ParentReport r;
  final Knowledge kb;

  @override
  Widget build(BuildContext context) => Panel(
        title: tr('知識點地圖', 'Topic map', 'Mapa de temas'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 4, children: [
            for (final s in KpStatus.values)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 12, color: s.color),
                const SizedBox(width: 4),
                Text('${s.label} ${kb.kps.where((k) => (r.kpStatus[k.id] ?? KpStatus.untested) == s).length}', style: pixelText(13)),
              ]),
          ]),
          for (final m in kb.modules) ...[
            const SizedBox(height: 12),
            Text('${m.label} · ${m.termLabel}', style: pixelText(15, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in kb.inModule(m.id))
                PixelBox(
                  color: Px.paper,
                  shadow: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10, color: (r.kpStatus[k.id] ?? KpStatus.untested).color),
                    const SizedBox(width: 6),
                    Text(k.label, style: pixelText(13)),
                  ]),
                ),
            ]),
          ],
        ]),
      );
}
