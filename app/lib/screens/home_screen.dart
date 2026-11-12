import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';
import 'package:uuid/uuid.dart';

import '../ai/ai_picker.dart';
import '../ai/ai_service.dart';
import '../ai/ai_usage.dart';
import '../game/game_widgets.dart';
import '../game/player.dart';
import '../i18n.dart';
import '../logic/hunt_controller.dart';
import '../models/hunt.dart';
import '../models/jail.dart';
import '../models/knowledge.dart';
import '../services/local_db.dart';
import '../services/settings.dart';
import '../theme/pixel_theme.dart';
import '../widgets/benny.dart';
import '../widgets/common.dart';
import '../widgets/hunt_card.dart';
import '../widgets/math_text.dart';
import '../widgets/turtles.dart';
import '../widgets/sprite.dart';
import '../widgets/world_map.dart';
import 'hunt/hunt_screen.dart';
import 'jail_screen.dart';
import 'monster_house_screen.dart';
import 'settings_screen.dart';
import 'treasure_chest_screen.dart';

/// 首页：Benny 和小加和小减、"发现错题怪兽"按钮、Benny 的冒险者卡片、战绩、怪兽屋（以前的错题）、冒险世界地图
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Knowledge? _kb;
  AppSettings? _settings;
  Map<String, KpInfo> _states = {};
  List<HuntSummary> _hunts = [];
  Map<String, VillageInfo> _villages = {};
  List<JailCase> _jail = [];
  HuntSession? _saved;
  String? _aiLabel;
  AiUsage? _usage;
  Player? _player;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Sprite.precache(context, [...Turtles.frames, ...Benny.frames]);
  }

  Future<void> _load() async {
    final kb = await Knowledge.load();
    final settings = await AppSettings.load();
    final saved = await SessionStore.load();
    final ai = await pickAi(kb);
    final usage = await AiUsage.load();
    final player = await PlayerStore.load();
    final db = LocalDb.instance;
    final states = await db.kpStates();
    final hunts = (await db.listHunts(limit: 30)).where((h) => h.stage != 'capture').toList();
    final villages = await db.listVillages();
    final jail = await db.listJail();
    if (!mounted) return;
    setState(() {
      _kb = kb;
      _settings = settings;
      _states = states;
      _hunts = hunts;
      _villages = villages;
      _jail = jail;
      _saved = saved != null && saved.stage != 'victory' ? saved : null;
      _aiLabel = ai?.label;
      _usage = usage;
      _player = player;
    });
  }

  Future<void> _openHunt(HuntSession session, {bool photoMode = false}) async {
    final AiService? ai = session.demo ? LocalDemoAi() : await pickAi(_kb!);
    if (!mounted) return;
    // 已经生成好修炼内容的不需要 AI；新的要先登录 ChatGPT
    final ready = session.trainingReady && (session.isVillage || session.readable);
    if (ai == null && !ready) {
      NesSnackbar.show(context, text: tr('還沒登入 ChatGPT：點右上角的設定登入。', 'Not signed in to ChatGPT yet: tap Settings in the top right.', 'Aún no has iniciado sesión en ChatGPT: toca Ajustes arriba a la derecha.'), type: NesSnackbarType.warning);
      return;
    }
    final controller = HuntController(session: session, settings: _settings!, kb: _kb!, ai: ai)..photoMode = photoMode;
    if (!session.isVillage) await SessionStore.save(session);
    await controller.refreshCases(); // 在监狱里提审过的题，拿回最新进度
    if (!mounted) return;
    // 村庄第一次修炼：进去就让 GPT 准备内容（只这一次，之后从存档读）
    if (session.isVillage && !session.trainingReady) unawaited(controller.waitForTraining());
    final result = await Navigator.of(context).push<Object?>(MaterialPageRoute(builder: (_) => HuntScreen(controller: controller)));
    // 拍题时认出是以前拍过的题：打开以前的存档
    if (result is OpenArchived) {
      await _openArchived(result.pid);
      return;
    }
    _load();
  }

  /// 打开以前的一道题：从数据库读存档，不调用 GPT。correct = 去订正（重新拍这道题，看对不对）
  Future<void> _openArchived(String pid, {bool correct = false}) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final session = await LocalDb.instance.getHunt(pid);
      if (correct && session.readable) {
        session.stage = 'boss';
        if (session.bossDone) {
          // 打过的 Boss 再订正一次：开新的一局
          session
            ..boss = QResult()
            ..selfCheck = null
            ..bossReported = false
            ..recheck = null
            ..bossRound += 1;
        }
      } else if (session.readable && session.stage == 'victory' && session.queue.isNotEmpty) {
        session.stage = 'learn';
      }
      await _openHunt(session, photoMode: correct);
    } catch (e) {
      if (mounted) NesSnackbar.show(context, text: tr('打不開這道題：$e', "Couldn't open this problem: $e", 'No se pudo abrir este problema: $e'), type: NesSnackbarType.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// 在冒险地图上点开一个村庄：有存档就读存档，没有就新建（进去后生成一次修炼内容）
  Future<void> _openVillage(String kpId) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final saved = await LocalDb.instance.getVillage(kpId);
      await _openHunt(saved ?? HuntSession.village(kpId));
    } catch (e) {
      if (mounted) NesSnackbar.show(context, text: tr('打不開這個村莊：$e', "Couldn't open this village: $e", 'No se pudo abrir esta aldea: $e'), type: NesSnackbarType.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openMonsterHouse() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MonsterHouseScreen(settings: _settings!, kb: _kb!, open: (pid, {correct = false}) => _openArchived(pid, correct: correct)),
    ));
    if (mounted) _load();
  }

  Future<void> _openJail() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JailScreen(settings: _settings!, kb: _kb!)));
    if (mounted) _load();
  }

  void _startHunt({bool demo = false}) {
    _openHunt(HuntSession(pid: const Uuid().v4(), demo: demo, status: demo ? '做错了' : ''));
  }

  Future<void> _discardSaved() async {
    await SessionStore.clear();
    setState(() => _saved = null);
  }

  Future<void> _openChest() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TreasureChestScreen(player: _player ?? Player([]), settings: _settings!)));
    final p = await PlayerStore.load(); // 可能卖掉了宝藏
    if (mounted) setState(() => _player = p);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final kb = _kb;
    if (kb == null) return const Scaffold(body: Center(child: NesHourglassLoadingIndicator()));
    final name = _settings?.studentName ?? 'Benny';
    final count = {for (final s in KpStatus.values) s: _states.values.where((i) => i.status == s).length};

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: pagePadding(context),
            children: [
              Row(children: [
                Expanded(child: Text(tr('$name 的數學冒險', "$name's Math Quest", 'La aventura matemática de $name'), style: pixelText(isNarrow(context) ? 22 : 28, weight: FontWeight.w700))),
                if (!isNarrow(context)) ...[_AiChip(label: _aiLabel, exhausted: _usage?.exhausted() ?? false), const SizedBox(width: 12)],
                NesTooltip(message: tr('設定', 'Settings', 'Ajustes'), child: NesIconButton(icon: NesIcons.wrench, size: const Size.square(28), onPress: _openSettings)),
              ]),
              if (isNarrow(context)) ...[const SizedBox(height: 6), Align(alignment: Alignment.centerLeft, child: _AiChip(label: _aiLabel, exhausted: _usage?.exhausted() ?? false))],
              const SizedBox(height: 16),
              _Hero(name: name, onHunt: _startHunt, onDemo: () => _startHunt(demo: true)),
              if (_player != null) ...[
                const SizedBox(height: 18),
                PlayerCard(player: _player!, onOpenChest: _openChest),
              ],
              if (_saved != null) ...[
                const SizedBox(height: 18),
                Panel(
                  title: tr('上次的怪獸還沒打完', "Last monster isn't beaten yet", 'El último monstruo aún no está vencido'),
                  color: Px.skyLight,
                  child: Row(children: [
                    Expanded(
                      child: MathText(
                        '${_saved!.analysis?['problem_text'] ?? tr('還在拍題這一步', 'Still taking photos', 'Todavía haciendo fotos')}${_saved!.demo ? tr('（示例）', ' (demo)', ' (ejemplo)') : ''}',
                        style: pixelText(16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    PxButton(tr('繼續打', 'Continue', 'Continuar'), onPressed: () => _openHunt(_saved!)),
                    const SizedBox(width: 8),
                    PxButton(tr('不打了', 'Drop it', 'Dejarlo'), type: NesButtonType.normal, onPressed: _discardSaved),
                  ]),
                ),
              ],
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: _StatBox(sprite: 'village_solid', label: tr('已掌握的知識點', 'Topics mastered', 'Temas dominados'), value: '${count[KpStatus.basic]! + count[KpStatus.solid]!}')),
                SizedBox(width: isNarrow(context) ? 8 : 14),
                Expanded(child: _StatBox(sprite: 'village_weak', label: tr('還被怪獸佔著', 'Held by monsters', 'En manos de monstruos'), value: '${count[KpStatus.weak]}')),
                SizedBox(width: isNarrow(context) ? 8 : 14),
                Expanded(child: _StatBox(sprite: 'village_untested', label: tr('去過的村莊', 'Villages visited', 'Aldeas visitadas'), value: '${_states.length} / ${kb.kps.length}')),
              ]),
              if (_usage?.exhausted() ?? false) ...[
                const SizedBox(height: 14),
                PixelBox(
                  color: Px.sunLight,
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const Turtles(size: 44, mood: TurtleMood.oops),
                      const SizedBox(width: 12),
                      Expanded(child: Text(quotaMessage(_usage!.recoverBy), style: pixelText(15))),
                    ]),
                    const SizedBox(height: 8),
                    const Align(alignment: Alignment.centerRight, child: ManageUsageButton(primary: true)),
                  ]),
                ),
              ],
              const SizedBox(height: 28),
              Row(children: [
                Expanded(child: _SectionTitle(tr('怪獸屋', 'Monster House', 'Casa de los Monstruos'), tr('以前抓到的錯題怪獸都住在這裡，隨時回來看、訂正、再打一遍', 'Every monster you have caught lives here. Come back to review, correct and fight again', 'Aquí viven todos los monstruos que has atrapado. Vuelve cuando quieras a repasar, corregir y luchar otra vez'))),
                PxButton(tr('進怪獸屋', 'Enter', 'Entrar'), icon: NesIcons.home, onPressed: _openMonsterHouse),
              ]),
              const SizedBox(height: 10),
              if (_hunts.isEmpty)
                PixelBox(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Sprite('monster_house', width: 56, height: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(tr('怪獸屋還空著。拍下第一隻錯題怪獸，它就會住進來。', 'The Monster House is empty. Snap your first mistake and its monster moves in.', 'La Casa de los Monstruos está vacía. Haz una foto de tu primer error y su monstruo se mudará aquí.'), style: pixelText(16, color: Px.shadow)),
                    ),
                  ]),
                )
              else
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _hunts.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => i < _hunts.length
                        ? HuntCard(h: _hunts[i], kb: kb, onTap: () => _openArchived(_hunts[i].pid), onCorrect: () => _openArchived(_hunts[i].pid, correct: true))
                        : GestureDetector(
                            onTap: _openMonsterHouse,
                            child: PixelBox(
                              width: 150,
                              color: Px.skyLight,
                              padding: const EdgeInsets.all(10),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Sprite('monster_house', width: 64, height: 64),
                                const SizedBox(height: 8),
                                Text(tr('看全部 →', 'See all →', 'Ver todos →'), style: pixelText(16, color: Px.sky)),
                              ]),
                            ),
                          ),
                  ),
                ),
              const SizedBox(height: 28),
              _JailSection(cases: _jail, onOpen: _openJail),
              const SizedBox(height: 28),
              _SectionTitle(tr('冒險世界地圖', 'Adventure Map', 'Mapa de aventuras'), tr('每個年級一塊大陸，每個知識點一個村莊。點村莊可以進去修煉', 'Each grade is a land and each topic is a village. Tap a village to train there', 'Cada curso es un continente y cada tema es una aldea. Toca una aldea para entrenar allí')),
              const SizedBox(height: 10),
              WorldMap(knowledge: kb, states: _states, villages: _villages, onOpen: _openVillage),
            ],
          ),
        ),
      ),
    );
  }
}

/// 怪兽监狱：放弃过的题关在这里，在不同的两天里自己做对才放出来
class _JailSection extends StatelessWidget {
  const _JailSection({required this.cases, required this.onOpen});
  final List<JailCase> cases;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final locked = cases.where((c) => !c.freed).toList();
    final today = locked.where(canRetryToday).length;
    final learning = locked.where((c) => !c.coachDone).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _SectionTitle(tr('怪獸監獄', 'Monster Jail', 'Cárcel de Monstruos'), tr('放棄過的題關在這裡，在不同的兩天裡自己做對才放出來', 'Problems you gave up on are locked here until you solve them yourself on two different days', 'Los problemas que abandonaste quedan encerrados aquí hasta que los resuelvas tú solo en dos días distintos'))),
        PxButton(tr('進監獄', 'Enter', 'Entrar'), icon: NesIcons.lock, onPressed: onOpen),
      ]),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: onOpen,
        child: PixelBox(
          color: locked.isEmpty ? Px.panel : Px.paperDim,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Sprite('monster_jail', width: 56, height: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                locked.isEmpty
                    ? tr('監獄是空的。放棄過的題會一步一步學會，然後關到這裡重點看管。', 'The jail is empty. Problems you give up on are learned step by step, then locked up here.', 'La cárcel está vacía. Los problemas que abandones se aprenden paso a paso y luego se encierran aquí.')
                    : tr('關著 ${locked.length} 只怪獸${today > 0 ? '，今天可以提審 $today 只' : ''}${learning > 0 ? '，還有 $learning 只沒一步一步學完' : ''}。',
                        '${locked.length} locked up${today > 0 ? ' · $today ready for a retrial today' : ''}${learning > 0 ? ' · $learning still to learn step by step' : ''}.', '${locked.length} encerrados${today > 0 ? ' · $today listos para el juicio de hoy' : ''}${learning > 0 ? ' · $learning por aprender paso a paso' : ''}.'),
                style: pixelText(16, color: locked.isEmpty ? Px.shadow : Px.ink),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.sub);
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) => Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 12, children: [
        Text(title, style: pixelText(24, weight: FontWeight.w700)),
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(sub, style: pixelText(14, color: Px.shadow))),
      ]);
}

class _AiChip extends StatelessWidget {
  const _AiChip({required this.label, required this.exhausted});
  final String? label;
  final bool exhausted;

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = label == null
        ? (tr('AI 未連線', 'AI not connected', 'IA sin conectar'), Px.brickLight, Px.brick)
        : exhausted
            ? (tr('AI 額度用完了', 'AI quota used up', 'Cuota de IA agotada'), Px.sunLight, Px.amber)
            : ('AI: $label', Px.grassLight, Px.okText);
    return PixelBox(
      color: bg,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(text, style: pixelText(13, color: fg)),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.name, required this.onHunt, required this.onDemo});

  final String name;
  final VoidCallback onHunt;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    final cast = Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Benny(height: wide ? 162 : 126),
      const SizedBox(width: 4),
      Turtles(size: wide ? 96 : 76),
    ]);
    final talk = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PixelBox(
          padding: const EdgeInsets.all(14),
          child: NesRunningText(
            text: tr('嗨 $name！今天有沒有遇到錯題怪獸？連題目帶解答拍下來，小加和小減幫你找到它的弱點，一起把它打敗！',
                'Hi $name! Met any mistake monsters today? Snap the problem with your working, and Plus and Minus will help you find its weak spot and beat it together!', '¡Hola, $name! ¿Te has encontrado hoy con algún monstruo de errores? Haz una foto del problema con tu resolución, ¡y Más y Menos te ayudarán a encontrar su punto débil para vencerlo juntos!'),
            textStyle: pixelText(18),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PxButton(tr('發現錯題怪獸（拍題）', 'Catch a mistake monster (photo)', 'Atrapa un monstruo de errores (foto)'), big: true, icon: NesIcons.camera, onPressed: onHunt),
          PxButton(tr('用示例題體驗', 'Try a demo', 'Prueba un ejemplo'), type: NesButtonType.normal, onPressed: onDemo),
        ]),
      ],
    );
    return PixelBox(
      color: Px.skyLight,
      padding: const EdgeInsets.fromLTRB(16, 14, 18, 16),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [cast, const SizedBox(width: 20), Expanded(child: talk)])
          : Column(children: [cast, const SizedBox(height: 14), talk]),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.sprite, required this.label, required this.value});

  final String sprite;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => PixelBox(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        // 手机上三格并排很窄：图在上、数字和说明在下
        child: isNarrow(context)
            ? Column(children: [
                Sprite(sprite, width: 32, height: 32),
                const SizedBox(height: 4),
                Text(value, style: pixelText(20, weight: FontWeight.w700)),
                Text(label, textAlign: TextAlign.center, style: pixelText(12, color: Px.shadow)),
              ])
            : Row(children: [
          Sprite(sprite, width: 48, height: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: pixelText(24, weight: FontWeight.w700)),
              Text(label, style: pixelText(14, color: Px.shadow)),
            ]),
          ),
        ]),
      );
}
