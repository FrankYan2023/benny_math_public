import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';

import '../game/monster_art.dart';
import '../i18n.dart';
import '../models/hunt.dart' show SessionStore;
import '../models/knowledge.dart';
import '../services/local_db.dart';
import '../services/settings.dart';
import '../theme/pixel_theme.dart';
import '../widgets/common.dart';
import '../widgets/hunt_card.dart';
import '../widgets/turtles.dart';
import '../widgets/sprite.dart';

/// 怪兽屋：以前抓到的错题怪兽都住在这里。点开可以再看图鉴、讲解、例题，小怪和 Boss 可以再打一遍。
/// 内容都从数据库读，不调用 GPT。
class MonsterHouseScreen extends StatefulWidget {
  const MonsterHouseScreen({super.key, required this.settings, required this.kb, required this.open});

  final AppSettings settings;
  final Knowledge kb;

  /// 打开一道以前的题（由首页负责：读存档、进打怪页面）；correct = 去订正
  final Future<void> Function(String pid, {bool correct}) open;

  @override
  State<MonsterHouseScreen> createState() => _MonsterHouseScreenState();
}

class _MonsterHouseScreenState extends State<MonsterHouseScreen> {
  List<HuntSummary>? _hunts;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final hunts = await LocalDb.instance.listHunts(limit: 200);
      if (mounted) setState(() => _hunts = hunts.where((h) => h.stage != 'capture').toList());
    } catch (e) {
      if (mounted) setState(() => _error = tr('讀不出存檔（$e）', "Couldn't read the saves ($e)", 'No se pudieron leer las partidas guardadas ($e)'));
    }
  }

  Future<void> _open(String pid, {bool correct = false}) async {
    await widget.open(pid, correct: correct);
    _load();
  }

  /// 放生：问一句，然后删掉这道题的存档（宝藏留着）
  Future<void> _release(HuntSummary h) async {
    final m = summaryMonster(h);
    final yes = await confirmBox(
      context,
      leading: MonsterAvatar(m, size: 80, defeated: h.done),
      title: tr('把${m.displayName}放生？', 'Release the ${m.displayName}?', '¿Liberar a ${m.displayName}?'),
      body: tr('放生以後，這道題的圖鑑、修煉和訂正記錄都會刪掉，再也打不開了。從它那裡拿到的寶藏還留在你的寶藏箱裡。',
          'Its guide, training and corrections will be deleted and cannot be opened again. Any treasure you got from it stays in your chest.', 'Se borrarán su guía, su entrenamiento y sus correcciones, y no se podrán volver a abrir. Los tesoros que conseguiste de él se quedan en tu cofre.'),
      ok: tr('放生', 'Release', 'Liberar'),
      cancel: tr('再想想', 'Not now', 'Ahora no'),
    );
    if (!yes || !mounted) return;
    try {
      await LocalDb.instance.deleteHunt(h.pid);
      if ((await SessionStore.load())?.pid == h.pid) await SessionStore.clear();
      if (!mounted) return;
      setState(() => _hunts = [for (final x in _hunts ?? <HuntSummary>[]) if (x.pid != h.pid) x]);
      NesSnackbar.show(context, text: tr('${m.displayName}回到大自然了。', 'The ${m.displayName} is free again.', '${m.displayName} vuelve a ser libre.'), type: NesSnackbarType.success);
    } catch (e) {
      if (mounted) NesSnackbar.show(context, text: tr('沒放生成功：$e', "Couldn't release it: $e", 'No se pudo liberar: $e'), type: NesSnackbarType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hunts = _hunts;
    final beaten = hunts?.where((h) => h.done).length ?? 0;
    final shown = switch (_filter) {
      'active' => hunts?.where((h) => !h.done).toList(),
      'done' => hunts?.where((h) => h.done).toList(),
      _ => hunts,
    };
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: pagePadding(context),
            children: [
              Row(children: [
                PxButton(tr('← 地圖', '← Map', '← Mapa'), type: NesButtonType.normal, onPressed: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('怪獸屋', 'Monster House', 'Casa de los Monstruos'), style: pixelText(isNarrow(context) ? 22 : 28, weight: FontWeight.w700))),
              ]),
              const SizedBox(height: 16),
              PixelBox(
                color: Px.skyLight,
                padding: const EdgeInsets.all(14),
                child: LeadRow(gap: 12, lead: [const Sprite('monster_house', width: 96, height: 96), const Turtles(size: 64)], child: Text(
                      hunts == null
                          ? tr('小加和小減在點名…', 'Plus and Minus are taking roll call…', 'Más y Menos están pasando lista…')
                          : hunts.isEmpty
                              ? tr('怪獸屋還空著。拍下第一隻錯題怪獸，它就會住進來。', 'The Monster House is empty. Snap your first mistake and its monster moves in.', 'La Casa de los Monstruos está vacía. Haz una foto de tu primer error y su monstruo se mudará aquí.')
                              : tr(
                                  '這裡住著 ${hunts.length} 只抓到過的錯題怪獸，已經打敗 $beaten 只。隨時回來看講解和例題，點"訂正"重新拍這道題，小怪和 Boss 也可以再打一遍（寶藏每隻怪獸只有一件，拿過就沒有了）。不想留的怪獸可以放生。',
                                  '${hunts.length} monsters live here and you have beaten $beaten. Come back any time to review, tap "Correct it" to photograph a fixed solution, or fight the minions and Boss again (each monster has only one treasure). You can release the ones you no longer need.', 'Aquí viven ${hunts.length} monstruos y has vencido a $beaten. Vuelve cuando quieras a repasar, toca «Corregir» para hacer foto de una solución corregida, o lucha otra vez contra los secuaces y el Jefe (cada monstruo tiene un solo tesoro). Puedes liberar los que ya no necesites.',
                                ),
                      style: pixelText(17),
                    )),
              ),
              const SizedBox(height: 16),
              if (hunts != null && hunts.isNotEmpty)
                Wrap(spacing: 10, runSpacing: 8, children: [
                  for (final (key, name) in [
                    ('all', tr('全部 ${hunts.length}', 'All ${hunts.length}', 'Todos ${hunts.length}')),
                    ('active', tr('還沒打敗 ${hunts.length - beaten}', 'Not beaten ${hunts.length - beaten}', 'Sin vencer ${hunts.length - beaten}')),
                    ('done', tr('已經打敗 $beaten', 'Beaten $beaten', 'Vencidos $beaten')),
                  ])
                    PxButton(name, type: _filter == key ? NesButtonType.primary : NesButtonType.normal, onPressed: () => setState(() => _filter = key)),
                ]),
              const SizedBox(height: 16),
              if (_error != null) Text(_error!, style: pixelText(15, color: Px.brick)),
              if (hunts == null && _error == null) const Center(child: NesHourglassLoadingIndicator()),
              if (shown != null)
                Wrap(spacing: 14, runSpacing: 14, children: [
                  for (final h in shown)
                    SizedBox(
                      height: 230,
                      child: HuntCard(h: h, kb: widget.kb, onTap: () => _open(h.pid), onCorrect: () => _open(h.pid, correct: true), onRelease: () => _release(h)),
                    ),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
