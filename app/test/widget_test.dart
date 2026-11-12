import 'package:benny_math/models/knowledge.dart';
import 'package:benny_math/theme/pixel_theme.dart';
import 'package:benny_math/services/local_db.dart';
import 'package:benny_math/widgets/benny.dart';
import 'package:benny_math/widgets/turtles.dart';
import 'package:benny_math/widgets/sprite.dart';
import 'package:benny_math/widgets/world_map.dart';
import 'package:flutter/material.dart';
import 'package:benny_math/game/game_data.dart';
import 'package:benny_math/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await GameData.load();
    i18n.setForTest(Lang.zh);
  });

  test('知识点清单能读出来：122 个，编号唯一，前置都存在', () async {
    final kb = await Knowledge.load();
    expect(kb.kps.length, 122);
    expect(kb.byId.length, 122);
    for (final k in kb.kps) {
      for (final p in k.pre) {
        expect(kb.byId.containsKey(p), isTrue, reason: '${k.id} 的前置 $p 不存在');
      }
    }
  });

  test('状态解析：未知值当作未检测', () {
    expect(KpStatus.parse('weak'), KpStatus.weak);
    expect(KpStatus.parse(null), KpStatus.untested);
    expect(KpStatus.parse('???'), KpStatus.untested);
  });

  testWidgets('小加和小减的每种表情都能画出来', (tester) async {
    for (final mood in TurtleMood.values) {
      await tester.pumpWidget(MaterialApp(home: Center(child: Turtles(size: 64, mood: mood))));
      expect(find.byType(Turtles), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  test('地图布局：每个知识点都有村庄，村庄之间不挤在一起', () async {
    final kb = await Knowledge.load();
    final layout = await WorldMapLayout.load();
    for (final k in kb.kps) {
      expect(layout.villages[k.id], isNotNull, reason: '${k.id} 没有村庄');
    }
    final pts = [for (final k in kb.kps) layout.villages[k.id]!];
    for (var i = 0; i + 1 < pts.length; i++) {
      expect((pts[i] - pts[i + 1]).distance, greaterThan(14), reason: '${kb.kps[i].id} 和下一个村庄太近');
    }
    expect(layout.signs.length, kb.modules.length, reason: '每章一个木牌');
  });

  testWidgets('地图：按状态画村庄，Benny 站在最近学过的村庄，点村庄弹出说明', (t) async {
    t.view.physicalSize = const Size(1180, 820) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final kb = (await t.runAsync(Knowledge.load))!;
    await t.runAsync(WorldMapLayout.load);
    final states = {'7A-2-02': const KpInfo(KpStatus.weak, 2000), '7A-1-04': const KpInfo(KpStatus.basic, 1000)};
    await t.pumpWidget(MaterialApp(
      theme: buildPixelTheme(),
      home: Scaffold(body: SingleChildScrollView(child: WorldMap(knowledge: kb, states: states))),
    ));
    await t.pump(const Duration(milliseconds: 100));
    final names = t.widgetList<Sprite>(find.byType(Sprite)).map((s) => s.name).toList();
    expect(names.where((n) => n.startsWith('village_')).length, greaterThanOrEqualTo(122));
    expect(names.where((n) => n == 'village_weak').length, 2, reason: '地图上 1 个 + 图例 1 个');
    expect(find.byType(BennyWalker), findsOneWidget);
    await t.tap(find.bySemanticsLabel(RegExp('有理數減法')));
    await t.pump();
    expect(find.text('有理數減法'), findsOneWidget);
    expect(find.textContaining('進入修煉'), findsNothing, reason: '没有 onOpen 时不显示进入按钮');

    String? opened;
    await t.pumpWidget(MaterialApp(
      theme: buildPixelTheme(),
      home: Scaffold(
        body: SingleChildScrollView(child: WorldMap(key: const ValueKey('open'), knowledge: kb, states: states, onOpen: (id) => opened = id)),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.bySemanticsLabel(RegExp('有理數減法：')).first);
    await t.pump();
    expect(find.textContaining('第一次進去'), findsOneWidget);
    await t.tap(find.textContaining('進入修煉'));
    expect(opened, '7A-2-02');
    await t.pumpWidget(const SizedBox());
  });

}
