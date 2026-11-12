import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nes_ui/nes_ui.dart';

import '../i18n.dart';
import '../models/knowledge.dart';
import '../services/local_db.dart';
import '../theme/pixel_theme.dart';
import 'benny.dart';
import 'common.dart' show PxButton;
import 'pixel_box.dart';
import 'sprite.dart';

/// 地图布局（assets/art/worldmap.json，由 tool/art/build.py 生成）：坐标都是地图像素
class WorldMapLayout {
  WorldMapLayout._(this.size, this.villages, this.regions, this.signs);

  final Size size;
  final Map<String, Offset> villages;
  final List<({String name, String nameEn, String nameEs, Offset at, bool locked})> regions; // name 是繁体中文
  final List<({String module, String name, Offset at})> signs;

  static WorldMapLayout? _cache;

  static Future<WorldMapLayout> load() async {
    if (_cache != null) return _cache!;
    final j = jsonDecode(await rootBundle.loadString('assets/art/worldmap.json')) as Map<String, dynamic>;
    Offset at(Object? x, Object? y) => Offset((x as num).toDouble(), (y as num).toDouble());
    final size = j['size'] as List;
    return _cache = WorldMapLayout._(
      Size((size[0] as num).toDouble(), (size[1] as num).toDouble()),
      {for (final e in (j['villages'] as Map).entries) e.key as String: at((e.value as List)[0], (e.value as List)[1])},
      [
        for (final r in (j['regions'] as List).cast<Map>())
          (
            name: r['name_hant'] as String? ?? r['name'] as String,
            nameEn: r['name_en'] as String? ?? r['name'] as String,
            nameEs: r['name_es'] as String? ?? r['name'] as String,
            at: at(r['x'], r['y']),
            locked: r['locked'] == true,
          ),
      ],
      [for (final s in (j['signs'] as List).cast<Map>()) (module: s['module'] as String, name: s['name'] as String, at: at(s['x'], s['y']))],
    );
  }
}

/// 村庄的样子 ↔ 掌握状态
String villageSprite(KpStatus s) => 'village_${s.name}';
Map<KpStatus, String> get villageNames => {
      KpStatus.solid: tr('城堡 · 熟練', 'Castle · Mastered', 'Castillo · Dominado'),
      KpStatus.basic: tr('小屋 · 基本掌握', 'House · Got it', 'Casa · Lo tiene'),
      KpStatus.learning: tr('在蓋的房子 · 學習中', 'Building · Learning', 'Obra · Aprendiendo'),
      KpStatus.weak: tr('怪獸營地 · 薄弱', 'Monster camp · Weak', 'Campamento de monstruos · Débil'),
      KpStatus.untested: tr('沒去過 · 未檢測', 'Unvisited · Untested', 'Sin visitar · Sin evaluar'),
    };

/// 冒险世界地图：每个年级一块陆地，每个知识点一个村庄，Benny 站在最近学习的那个村庄。
class WorldMap extends StatefulWidget {
  const WorldMap({super.key, required this.knowledge, required this.states, this.villages = const {}, this.onOpen, this.zoomable = true});

  final Knowledge knowledge;
  final Map<String, KpInfo> states;
  final Map<String, VillageInfo> villages; // 已经有修炼内容的村庄
  final void Function(String kpId)? onOpen; // 进入村庄修炼
  final bool zoomable;

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap> {
  WorldMapLayout? _layout;
  String? _selected;

  @override
  void initState() {
    super.initState();
    WorldMapLayout.load().then((l) {
      if (mounted) setState(() => _layout = l);
    });
  }

  KpStatus _status(String id) => widget.states[id]?.status ?? KpStatus.untested;

  /// Benny 站的地方：最近学过的知识点；还没学过就在出发村
  String? get _bennyAt {
    final touched = widget.states.entries.where((e) => e.value.lastAt > 0).toList()..sort((a, b) => b.value.lastAt.compareTo(a.value.lastAt));
    if (touched.isNotEmpty && _layout!.villages.containsKey(touched.first.key)) return touched.first.key;
    return widget.knowledge.kps.isEmpty ? null : widget.knowledge.kps.first.id;
  }

  void _openFull() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(tr('冒險世界地圖', 'Adventure Map', 'Mapa de aventuras'), style: pixelText(20)), backgroundColor: Px.paper),
          body: InteractiveViewer(
            constrained: false,
            minScale: 0.5,
            maxScale: 4,
            child: SizedBox(
              width: 640 * 3,
              child: WorldMap(
                knowledge: widget.knowledge,
                states: widget.states,
                villages: widget.villages,
                onOpen: widget.onOpen == null
                    ? null
                    : (id) {
                        Navigator.of(context).pop();
                        widget.onOpen!(id);
                      },
                zoomable: false,
              ),
            ),
          ),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    if (layout == null) return const AspectRatio(aspectRatio: 1.6, child: Center(child: NesHourglassLoadingIndicator()));
    final counts = {for (final s in KpStatus.values) s: widget.knowledge.kps.where((k) => _status(k.id) == s).length};

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PixelBox(
        color: Px.sky,
        child: LayoutBuilder(builder: (context, box) {
          final scale = box.maxWidth / layout.size.width;
          final selected = _selected;
          final benny = _bennyAt;
          return SizedBox(
            width: box.maxWidth,
            height: layout.size.height * scale,
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              Positioned.fill(child: GestureDetector(onTap: () => setState(() => _selected = null), child: const Sprite('worldmap'))),
              for (final r in layout.regions) _Banner(tr(r.name, r.nameEn, r.nameEs), r.at * scale, locked: r.locked, size: (13 * scale / 1.75).clamp(11, 22)),
              for (final s in layout.signs) _Sign(_signLabel(s.module, widget.knowledge.modules.where((m) => m.id == s.module).firstOrNull?.shortLabel ?? s.name), s.at * scale, scale, alignRight: s.at.dx > layout.size.width - 90),
              for (final k in widget.knowledge.kps)
                if (layout.villages[k.id] case final at?)
                  Positioned(
                    left: (at.dx - 10) * scale,
                    top: (at.dy - 14) * scale,
                    width: 20 * scale,
                    height: 20 * scale,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selected = _selected == k.id ? null : k.id),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(2 * scale, 2 * scale, 2 * scale, 2 * scale),
                        child: Sprite(villageSprite(_status(k.id)), semanticLabel: '${k.label}：${_status(k.id).label}'),
                      ),
                    ),
                  ),
              if (benny != null && layout.villages[benny] != null)
                Positioned(
                  left: (layout.villages[benny]!.dx - 8) * scale,
                  top: (layout.villages[benny]!.dy - 31) * scale,
                  child: IgnorePointer(child: BennyWalker(scale: scale)),
                ),
              if (selected != null && layout.villages[selected] != null)
                _Bubble(
                  kp: widget.knowledge.byId[selected]!,
                  status: _status(selected),
                  module: widget.knowledge.modules.where((m) => m.id == widget.knowledge.byId[selected]!.module).firstOrNull?.label ?? '',
                  village: widget.villages[selected],
                  at: layout.villages[selected]! * scale,
                  scale: scale,
                  mapSize: Size(box.maxWidth, layout.size.height * scale),
                  onClose: () => setState(() => _selected = null),
                  onOpen: widget.onOpen == null
                      ? null
                      : () {
                          setState(() => _selected = null);
                          widget.onOpen!(selected);
                        },
                ),
            ]),
          );
        }),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 18, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final s in KpStatus.values)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Sprite(villageSprite(s), width: 32, height: 32),
            const SizedBox(width: 6),
            Text('${villageNames[s]} ${counts[s]}', style: pixelText(14, color: Px.shadow)),
          ]),
        if (widget.zoomable) TextButton(onPressed: _openFull, child: Text(tr('放大看地圖 →', 'Zoom in →', 'Ampliar →'), style: pixelText(15, color: Px.sky))),
      ]),
    ]);
  }

  String _signLabel(String module, String name) {
    final n = RegExp(r'-(\d+)$').firstMatch(module)?.group(1);
    return n == null ? name : tr('第$n章 $name', 'Ch.$n $name', 'Tema $n $name');
  }
}

/// 区域名：像素横幅
class _Banner extends StatelessWidget {
  const _Banner(this.text, this.at, {required this.locked, required this.size});
  final String text;
  final Offset at;
  final bool locked;
  final double size;

  @override
  Widget build(BuildContext context) => Positioned(
        left: at.dx,
        top: at.dy,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: IgnorePointer(
            child: PixelBox(
              color: locked ? Px.paperDim : Px.panel,
              border: locked ? Px.shadow : Px.ink,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: Text(locked ? tr('$text（還沒開放）', '$text (locked)', '$text (bloqueado)') : text, style: pixelText(size, color: locked ? Px.shadow : Px.ink, weight: FontWeight.w700)),
            ),
          ),
        ),
      );
}

/// 每章开头的木牌
class _Sign extends StatelessWidget {
  const _Sign(this.text, this.at, this.scale, {required this.alignRight});
  final String text;
  final Offset at;
  final double scale;
  final bool alignRight; // 靠地图右边的牌子往左挂，不出界

  @override
  Widget build(BuildContext context) {
    final size = (9 * scale / 1.75).clamp(9.0, 18.0);
    return Positioned(
      left: alignRight ? null : at.dx - 4 * scale,
      right: alignRight ? 6 : null,
      top: at.dy - 14 * scale - size * 1.25 - 6,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: const Color(0xe69a6b3e), border: Border.all(color: const Color(0xff4a2f1f), width: 1.5)),
          child: Text(text, style: pixelText(size, color: Colors.white).copyWith(height: 1.2)),
        ),
      ),
    );
  }
}

/// 点村庄弹出的说明，可以进入修炼
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.kp,
    required this.status,
    required this.module,
    required this.village,
    required this.at,
    required this.scale,
    required this.mapSize,
    required this.onClose,
    required this.onOpen,
  });
  final KnowledgePoint kp;
  final KpStatus status;
  final String module;
  final VillageInfo? village;
  final Offset at;
  final double scale;
  final Size mapSize;
  final VoidCallback onClose;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    const w = 280.0;
    final left = (at.dx - w / 2).clamp(4.0, mapSize.width - w - 4);
    final below = at.dy < mapSize.height * 0.55; // 地图下半部分的村庄，说明框放在上面
    final tier = kp.tierLabel;
    final v = village;
    final note = v == null
        ? tr('第一次進去，小加和小減要先準備修煉內容（大約半分鐘）', 'First visit: Plus and Minus need about half a minute to prepare the training', 'Primera visita: Más y Menos necesitan medio minuto para preparar el entrenamiento')
        : v.finished
            ? tr('修煉過了：打倒 ${v.defeated}/${v.total} 只小怪，可以再看講解和例題', 'Trained: defeated ${v.defeated}/${v.total}. Review the lesson and example any time', 'Entrenado: vencidos ${v.defeated}/${v.total}. Repasa la lección y el ejemplo cuando quieras')
            : tr('修煉內容準備好了${v.defeated > 0 ? '，已經打倒 ${v.defeated}/${v.total} 只小怪' : ''}', 'Training ready${v.defeated > 0 ? ' — defeated ${v.defeated}/${v.total} so far' : ''}', 'Entrenamiento listo${v.defeated > 0 ? ': vencidos ${v.defeated}/${v.total} hasta ahora' : ''}');
    return Positioned(
      left: left,
      top: below ? at.dy + 8 * scale : null,
      bottom: below ? null : mapSize.height - at.dy + 16 * scale,
      width: w,
      child: GestureDetector(
        onTap: onClose,
        child: PixelBox(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(kp.label, style: pixelText(17, weight: FontWeight.w700)),
            Text('$module · $tier', style: pixelText(13, color: Px.shadow)),
            const SizedBox(height: 4),
            Row(children: [
              Sprite(villageSprite(status), width: 24, height: 24),
              const SizedBox(width: 6),
              Text(status.label, style: pixelText(15, color: status == KpStatus.untested ? Px.shadow : status.color, weight: FontWeight.w700)),
            ]),
            if (onOpen != null) ...[
              const SizedBox(height: 6),
              Text(note, style: pixelText(13, color: Px.shadow)),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: PxButton(v == null ? tr('進入修煉', 'Start training', 'Empezar a entrenar') : tr('繼續修煉', 'Continue training', 'Seguir entrenando'), icon: NesIcons.sword, onPressed: onOpen)),
            ],
          ]),
        ),
      ),
    );
  }
}
