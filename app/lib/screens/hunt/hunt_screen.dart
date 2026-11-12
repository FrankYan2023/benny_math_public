import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../../game/game_widgets.dart';
import '../../game/treasure.dart';
import '../../i18n.dart';
import '../../logic/hunt_controller.dart';
import '../../models/hunt.dart';
import '../../theme/pixel_theme.dart';
import '../../widgets/common.dart';
import 'analysis_view.dart';
import 'boss_view.dart';
import 'capture_view.dart';
import 'lesson_view.dart';
import 'victory_view.dart';

/// 一次打怪的全流程：拍题 → 怪兽图鉴 → 修炼（讲解、例题、打小怪）→ Boss 战 → 胜利
class HuntScreen extends StatefulWidget {
  const HuntScreen({super.key, required this.controller});
  final HuntController controller;

  @override
  State<HuntScreen> createState() => _HuntScreenState();
}

class _HuntScreenState extends State<HuntScreen> {
  final _scroll = ScrollController();
  String _lastView = '';

  HuntController get c => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    c.dispose();
    super.dispose();
  }

  static Map<String, String> get _titles => {
        'capture': tr('發現錯題怪獸', 'Catch a Mistake Monster', 'Atrapa un monstruo de errores'),
        'analysis': tr('怪獸圖鑑', 'Monster Guide', 'Guía de Monstruos'),
        'learn': tr('修煉', 'Training', 'Entrenamiento'),
        'boss': tr('Boss 戰', 'Boss Fight', 'Batalla final'),
        'victory': tr('勝利！', 'Victory!', '¡Victoria!'),
      };

  /// 换页面时回到顶部
  void _scrollTopIfChanged(String view) {
    if (view == _lastView) return;
    _lastView = view;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.session;
        final l = s.currentLesson;
        _scrollTopIfChanged('${s.stage}/${s.kpIndex}/${l?.tab}/${l?.q}');
        final body = switch (s.stage) {
          'analysis' => AnalysisView(c: c),
          'learn' => LessonView(c: c),
          'boss' => BossView(c: c),
          'victory' => VictoryView(c: c),
          _ => CaptureView(c: c),
        };
        return Scaffold(
          body: Stack(children: [
            SafeArea(
              child: Column(children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(isNarrow(context) ? 12 : 16, 12, isNarrow(context) ? 12 : 16, 4),
                  child: Row(children: [
                    PxButton(tr('← 地圖', '← Map', '← Mapa'), type: NesButtonType.normal, onPressed: () => Navigator.of(context).pop()),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.isVillage ? tr('村莊修煉', 'Village Training', 'Entrenamiento en la aldea') : _titles[s.stage] ?? '', style: pixelText(isNarrow(context) ? 20 : 24, weight: FontWeight.w700))),
                    if (s.demo) Text(tr('示例模式', 'Demo mode', 'Modo de ejemplo'), style: pixelText(14, color: Px.amber)),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: isNarrow(context) ? const EdgeInsets.fromLTRB(12, 10, 12, 40) : const EdgeInsets.fromLTRB(20, 12, 20, 48),
                    children: [
                      if (c.error != null) ...[
                        ErrorBanner(
                          error: c.error!,
                          onRetry: c.error!.retry == null ? null : () => c.error!.retry!(),
                          onClose: c.dismissError,
                        ),
                        const SizedBox(height: 16),
                      ],
                      body,
                    ],
                  ),
                ),
              ]),
            ),
            if (c.busy != null) Positioned.fill(child: BusyOverlay(busy: c.busy!, onCancel: c.cancelBusy, demo: s.demo)),
          ]),
        );
      },
    );
  }
}

/// 拍题时认出是以前拍过的题：关掉这一页，让首页打开以前的存档
class OpenArchived {
  const OpenArchived(this.pid);
  final String pid;
}

/// 页面之间的间距
const gap = SizedBox(height: 18);

/// 知识点名字 + 层级标签
class KpLabel extends StatelessWidget {
  const KpLabel(this.c, this.id, {super.key, this.size = 17});
  final HuntController c;
  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kp = c.kb.byId[id];
    final tier = kp?.tierLabel ?? '';
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
      Text(kp?.label ?? id, style: pixelText(size, weight: FontWeight.w700)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(border: Border.all(color: kp?.tier == 'e' ? Px.amber : Px.sky, width: 2)),
        child: Text(tier, style: pixelText(12, color: kp?.tier == 'e' ? Px.amber : Px.sky)),
      ),
    ]);
  }
}

String levelOf(Map<String, dynamic> q) => levels.contains(q['level']) ? q['level'] as String : '提高';

/// 难度、错因这些内部用中文的值，显示时按语言翻译
String levelLabel(String level) => switch (level) {
      '基础' => tr('基礎', 'Basic', 'Básico'),
      '变式' => tr('變式', 'Variation', 'Variante'),
      '提高' => tr('提高', 'Advanced', 'Avanzado'),
      '挑战' => tr('挑戰', 'Challenge', 'Reto'),
      _ => level,
    };
String errorLabel(String type) => switch (type) {
      '计算失误' => tr('計算失誤', 'Calculation slip', 'Fallo de cálculo'),
      '概念不清' => tr('概念不清', 'Concept mix-up', 'Concepto confuso'),
      '方法不会' => tr('方法不會', 'Stuck on the method', 'No sabía el método'),
      '审题错误' => tr('審題錯誤', 'Misread the question', 'Leyó mal el enunciado'),
      '前置缺失' => tr('前置缺失', 'Missing basics', 'Faltan bases'),
      '未作答' => tr('未作答', 'Not answered', 'Sin responder'),
      '无错误' => tr('無錯誤', 'No mistake', 'Sin errores'),
      _ => type,
    };

/// 这只怪兽（这个村庄）的宝藏：刚拿到就开宝箱；拿过了说一声；还没拿到说还差什么
class HuntTreasure extends StatelessWidget {
  const HuntTreasure({super.key, required this.c, this.quietIfTaken = false});
  final HuntController c;
  final bool quietIfTaken; // 拿过了就不提（Boss 战里用）

  @override
  Widget build(BuildContext context) {
    final s = c.session;
    final j = s.monsterTreasure;
    final who = s.isVillage ? tr('這個村莊', 'this village', 'esta aldea') : s.monsterTraits.displayName;
    if (j != null) {
      final t = Treasure.fromJson(j);
      if (c.lastTreasure?.id == t.id) return TreasureReveal(key: ValueKey(t.id), t: t, levelUp: c.levelUp);
      if (quietIfTaken) return const SizedBox.shrink();
      return Text(
        tr('$who的寶藏「${t.name}」已經拿到了，一隻怪獸只有一件。再打一遍是為了練得更熟。',
            "You already have the treasure from $who (${t.name}) — there's only one each. Fighting again makes you sharper.", 'Ya tienes el tesoro de $who (${t.name}): solo hay uno. Volver a luchar te hace más fuerte.'),
        style: pixelText(15, color: Px.shadow),
      );
    }
    final left = c.lessonsLeft;
    if (left == 0) return const SizedBox.shrink(); // 刚打完，宝藏马上就到
    return Text(
      tr('再修煉完 $left 個知識點，$who就會掉下它的寶藏。', 'Finish $left more topic${left > 1 ? 's' : ''} and $who will drop its treasure.', 'Termina $left tema${left > 1 ? 's' : ''} más y $who soltará su tesoro.'),
      style: pixelText(15, color: Px.amber, weight: FontWeight.w700),
    );
  }
}
