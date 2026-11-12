import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:benny_math/logic/hunt_controller.dart';
import 'package:benny_math/models/hunt.dart';
import 'package:benny_math/models/knowledge.dart';
import 'package:benny_math/models/jail.dart';
import 'package:benny_math/screens/hunt/hunt_screen.dart';
import 'package:benny_math/screens/jail_screen.dart';
import 'package:benny_math/services/local_db.dart';
import 'package:benny_math/services/settings.dart';
import 'package:benny_math/theme/pixel_theme.dart';
import 'package:flutter/material.dart';
import 'package:benny_math/game/game_data.dart';
import 'package:benny_math/i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

// 1×1 的 PNG，当作拍的照片
final photo = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));

/// 用界面点按走完整个流程：每个按钮只点一次就要生效
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await GameData.load();
    i18n.setForTest(Lang.zh);
    LocalDb.useDirectory(Directory.systemTemp.createTempSync('benny-test-'));
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 页面上有小加和小减的定时动画，不能用 pumpAndSettle，固定往前推一点时间
  Future<void> step(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 500));
  }

  // 等后台的事做完（分析、生成修炼、拆步骤）：按条件等，不按固定时间，机器忙的时候也不会误判
  Future<void> waitFor(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(done(), isTrue, reason: '等了 2 秒还没好');
    await step(t);
  }

  Future<void> tapText(WidgetTester t, String text) async {
    final f = find.textContaining(text);
    expect(f, findsWidgets, reason: '找不到"$text"');
    await t.ensureVisible(f.last);
    await t.pump();
    await t.tap(f.last);
    await step(t);
  }

  testWidgets('拍题 → 分析 → 修炼（标签随时切换）→ 打小怪 → Boss 战 → 胜利，每步点一次', (t) async {
    t.view.physicalSize = const Size(1180, 820) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    final kb = await t.runAsync(Knowledge.load);
    final ai = FakeAi(missing: ['7A-2-02']);
    final c = HuntController(
      session: HuntSession(pid: 'ui-test', status: '做错了'),
      settings: AppSettings(),
      kb: kb!,
      ai: ai,
      db: FakeDb(),
    )..addPhotos([photo, photo]);

    await t.pumpWidget(MaterialApp(theme: buildPixelTheme(), home: HuntScreen(controller: c)));
    await step(t);
    expect(find.textContaining('已拍 2 張'), findsOneWidget);

    await tapText(t, '召喚怪獸圖鑑');
    await waitFor(t, () => c.session.stage == 'analysis' && c.session.trainingReady);
    expect(find.textContaining('糊塗蟲'), findsWidgets);
    expect(find.textContaining('修煉內容準備好了'), findsOneWidget);

    await tapText(t, '開始修煉');
    expect(c.session.stage, 'learn');
    expect(find.textContaining('a-b=a+(-b)'), findsWidgets);

    // 标签随时切换：先去打一只小怪，再回去看讲解和例题
    await tapText(t, '打小怪 0/4');
    await t.enterText(find.byType(TextField), '8');
    await tapText(t, '出招');
    expect(c.session.currentLesson!.results[0]!.correct, isTrue);
    await tapText(t, '例題');
    expect(c.session.currentLesson!.tab, 'example');
    await tapText(t, '講解');
    expect(find.textContaining('a-b=a+(-b)'), findsWidgets);
    await tapText(t, '打小怪 1/4');
    expect(find.textContaining('下一隻'), findsOneWidget, reason: '回来时第 1 只还是打倒的状态');

    await tapText(t, '下一隻');
    await t.enterText(find.byType(TextField), '2');
    await tapText(t, '出招');
    await tapText(t, '下一隻');
    await t.enterText(find.byType(TextField), '2');
    await tapText(t, '出招');
    await tapText(t, '下一隻');
    await tapText(t, '13');
    expect(find.text('修煉成功！'), findsOneWidget);

    await tapText(t, '去打 Boss');
    expect(c.session.stage, 'boss');
    await t.enterText(find.byType(TextField), '2');
    await tapText(t, '出招');
    expect(c.session.bossWon, isTrue);
    await tapText(t, '收進怪獸屋');
    expect(c.session.stage, 'victory');
    expect(find.textContaining(RegExp('打敗了.*糊塗蟲')), findsOneWidget);
    expect(ai.calls, ['analyze', 'training']);

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Boss 战放弃：不直接给答案，一步一步来；第 2 步拍照判错先说错在哪里再给正确的，最后才给答案', (t) async {
    t.view.physicalSize = const Size(1180, 820) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    final kb = await t.runAsync(Knowledge.load);
    final ai = FakeAi(missing: [], stepVerdicts: ['错', '对']);
    final c = HuntController(
      session: HuntSession(pid: 'ui-coach', status: '做错了'),
      settings: AppSettings(),
      kb: kb!,
      ai: ai,
      db: FakeDb(),
    )..addPhotos([photo]);
    await t.runAsync(c.analyze);
    c.goToBoss();

    await t.pumpWidget(MaterialApp(theme: buildPixelTheme(), home: HuntScreen(controller: c)));
    await step(t);
    expect(find.textContaining('標準解法'), findsNothing, reason: '没打赢不给看标准解法');

    await tapText(t, '我放棄，一步一步來');
    await waitFor(t, () => c.bossCoach?.c.at == 1);
    expect(c.session.bossDone, isTrue);
    expect(find.textContaining('小加和小減講給你看'), findsOneWidget, reason: '第 1 步讲给他看');
    expect(find.textContaining('第 2 步 · 輪到你了'), findsOneWidget);
    expect(find.textContaining('异号相加'), findsOneWidget, reason: '这一步的提示');
    expect(find.textContaining('代回去看看'), findsNothing, reason: '后面几步的提示还没出现');
    expect(find.textContaining('最後的答案：'), findsNothing);

    // 拍照检查第 2 步：判错
    c.bossCoach!.photos.add([photo]);
    await step(t);
    await tapText(t, '檢查這一步');
    await waitFor(t, () => c.bossCoach!.c.at == 2);
    expect(find.textContaining('錯在哪裡：减号没变'), findsOneWidget);
    expect(find.textContaining('正確的這一步：'), findsOneWidget);
    expect(find.textContaining('第 3 步 · 輪到你了'), findsOneWidget);

    // 第 3 步说不会，直接讲
    await tapText(t, '這一步我不會');
    expect(c.bossCoach!.c.coachDone, isTrue);
    expect(find.textContaining('最後的答案：'), findsOneWidget);
    expect(find.textContaining('怪獸監獄'), findsWidgets);
    expect(ai.calls, ['analyze', 'steps', 'stepcheck']);

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('监狱提审：不显示步骤，输入答案做对记一次刑期', (t) async {
    t.view.physicalSize = const Size(1180, 820) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final c = JailCase(
      id: 'p9~boss', pid: 'p9', source: 'boss', problem: r'计算：$-3-(-5)$', answerType: '数值', accepted: ['2'], correctAnswer: '2',
      since: DateTime.now().millisecondsSinceEpoch - 3 * 24 * 3600 * 1000,
    )..coach = {'steps': [{'goal': '变号', 'hint': 'h', 'result': r'$-3+5$', 'explain': '秘密讲解'}], 'final_answer': '2', 'idea': ''};
    c.startCoach();
    await t.pumpWidget(MaterialApp(theme: buildPixelTheme(), home: JailCaseScreen(jailCase: c, settings: AppSettings(), ai: null)));
    await step(t);
    expect(find.textContaining('已經做對 0 / 2 次'), findsOneWidget);
    expect(find.textContaining('秘密讲解'), findsNothing, reason: '提审时看不到步骤');
    await t.enterText(find.byType(TextField), '2');
    await tapText(t, '出招');
    expect(c.wins, hasLength(1));
    expect(find.textContaining('已經做對 1 / 2 次'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
