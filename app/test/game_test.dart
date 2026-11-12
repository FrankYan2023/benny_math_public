import 'dart:convert';
import 'dart:io';

import 'package:benny_math/game/game_data.dart';
import 'package:benny_math/game/monster.dart';
import 'package:benny_math/game/player.dart';
import 'package:benny_math/game/treasure.dart';
import 'package:benny_math/i18n.dart';
import 'package:benny_math/logic/hunt_controller.dart';
import 'package:benny_math/models/hunt.dart';
import 'package:benny_math/models/knowledge.dart';
import 'package:benny_math/services/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Knowledge kb;
  setUpAll(() async {
    await GameData.load();
    kb = await Knowledge.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    i18n.setForTest(Lang.zh);
  });

  group('怪兽', () {
    test('名字 = 性格 + 外形 + 颜色 + 种类；重名就换一个没用过的组合', () {
      final a = MonsterTraits.unique(errorType: '计算失误', key: 'p1', personality: '调皮', look: '长角', color: '火红');
      expect(a.name, '调皮长角火红粗心鬼');
      final b = MonsterTraits.unique(errorType: '计算失误', key: 'p2', personality: '调皮', look: '长角', color: '火红', taken: {a.name});
      expect(b.name, isNot(a.name));
      expect(b.look, '长角', reason: '先换性格，外形和颜色尽量保持 GPT 挑的');
      final names = <String>{};
      for (var i = 0; i < 300; i++) {
        names.add(MonsterTraits.unique(errorType: '概念不清', key: 'k$i', personality: '糊涂', look: '三眼', color: '冰蓝', taken: names).name);
      }
      expect(names.length, 300, reason: '一直不重名');
    });

    test('英文名字', () {
      i18n.setForTest(Lang.en);
      final m = MonsterTraits.unique(errorType: '计算失误', key: 'p1', personality: '调皮', look: '长角', color: '火红');
      expect(m.displayName, 'Cheeky Horned Crimson Blunder Ghost');
      expect(m.name, '调皮长角火红粗心鬼', reason: '存档和去重用中文');
    });

    test('旧的题没存怪兽：按题目编号算，每次一样', () {
      expect(MonsterTraits.fromSeed('abc', '审题错误').name, MonsterTraits.fromSeed('abc', '审题错误').name);
      expect(MonsterTraits.fromSeed('abc', '审题错误').species, '马虎眼');
    });
  });

  group('宝藏和等级', () {
    LessonState lesson(List<QResult> rs, {int round = 1}) =>
        LessonState(data: fakeLesson('7A-2-02'), round: round, results: {for (final (i, r) in rs.indexed) i: r});

    test('稀有度：一次全对没提示是传说，全对是史诗，过关是稀有，其余普通；再打一遍最高稀有', () {
      QResult ok({int tries = 1, int hints = 0}) => QResult(tries: tries, correct: true, hints: hints);
      final bad = QResult(tries: 2, revealed: true);
      expect(lessonRarity(lesson([ok(), ok(), ok(), ok()])), 'legend');
      expect(lessonRarity(lesson([ok(), ok(tries: 2), ok(), ok(hints: 1)])), 'epic');
      expect(lessonRarity(lesson([ok(), ok(), bad, ok()])), 'rare');
      expect(lessonRarity(lesson([ok(), bad, bad, bad])), 'common');
      expect(lessonRarity(lesson([ok(), ok(), ok(), ok()], round: 2)), 'rare');
    });

    test('GPT 起的宝藏：能力名字换成编号，点数按稀有度，金币在稀有度的范围里', () {
      final t = fromGpt(id: 'x/1', spec: fakeLesson('7A-2-02')['treasure'] as Map<String, dynamic>, rarity: 'epic', source: 'lesson')!;
      expect(t.name, '变号之剑');
      expect(t.stats, {'calc': 3, 'focus': 3});
      expect(t.value, inInclusiveRange(80, 119));
    });

    test('App 组合的宝藏不和已有的重名', () {
      final owned = <String>{};
      for (var i = 0; i < 200; i++) {
        owned.add(procedural(id: 'p/$i', rarity: 'common', statIds: ['calc'], source: 'retry', owned: owned).name);
      }
      expect(owned.length, 200);
    });

    test('等级：能力总和 10 升 2 级、30 升 3 级；称号跟着等级', () {
      Treasure t(int n, int boost) => Treasure(id: 't$n', name: 'n$n', kind: '剑', material: '黄金', rarity: 'common', stats: {'calc': boost}, value: 10, story: '', source: 'lesson');
      expect(Player([]).level, 1);
      expect(Player([t(1, 9)]).level, 1);
      expect(Player([t(1, 5), t(2, 5)]).level, 2);
      expect(Player([for (var i = 0; i < 6; i++) t(i, 5)]).level, 3);
      expect(Player([t(1, 5), t(2, 5)]).title, '算術學徒');
      expect(Player([t(1, 5), t(2, 5)]).coins, 0, reason: '金币是卖宝藏换来的');
    });

    test('卖宝藏：换成金币，宝藏箱里少一件，能力和等级不变；后端记着卖掉的，合并后也算卖掉', () async {
      Treasure t(String id) => Treasure(id: id, name: id, kind: '剑', material: '黄金', rarity: 'common', stats: {'calc': 5}, value: 15, story: '', source: 'lesson');
      await PlayerStore.add(t('a'));
      await PlayerStore.add(t('b'));
      final sold = await PlayerStore.sell('a');
      expect(sold?.sold, isTrue);
      expect(await PlayerStore.sell('a'), isNull, reason: '不能卖两次');
      final p = await PlayerStore.load();
      expect(p.coins, 15);
      expect(p.owned.map((x) => x.id), ['b']);
      expect(p.power, 10, reason: '卖掉的宝藏加过的能力还在');
      expect(p.level, 2);
      expect(Treasure.fromJson(jsonDecode(jsonEncode(sold!.toJson()))).soldAt, sold.soldAt);

      final merged = await PlayerStore.merge([t('a'), t('b').soldOn(123)]);
      expect(merged.owned, isEmpty, reason: '本机卖的、后端卖的都算');
      expect(merged.coins, 30);
    });

    test('一只怪兽的宝藏稀有度按最差的那个修炼算', () {
      LessonState lesson(bool allRight) {
        final l = LessonState(data: fakeLesson('7A-2-02'));
        for (var i = 0; i < 4; i++) {
          l.resultOf(i)
            ..tries = 1
            ..correct = allRight || i > 0;
        }
        return l;
      }
      expect(huntRarity([lesson(true)]), 'legend');
      expect(huntRarity([lesson(true), lesson(false)]), lessonRarity(lesson(false)));
    });

    test('本机的宝藏和后端的合并，按编号去重', () async {
      final a = Treasure(id: 'a', name: 'A', kind: '剑', material: '黄金', rarity: 'common', stats: {'calc': 1}, value: 10, story: '', source: 'lesson');
      final b = Treasure(id: 'b', name: 'B', kind: '盾', material: '白银', rarity: 'common', stats: {'eye': 1}, value: 12, story: '', source: 'lesson');
      final (before, after) = await PlayerStore.add(a);
      expect(before.treasures, isEmpty);
      expect(after.treasures.length, 1);
      expect((await PlayerStore.add(a)).$2.treasures.length, 1, reason: '同一件不加两次');
      expect((await PlayerStore.merge([a, b])).treasures.length, 2);
    });
  });

  group('打怪流程里的怪兽、宝藏、订正', () {
    HuntController make(FakeAi ai, FakeDb backend, {String pid = 'game-1', String status = '做错了'}) =>
        HuntController(session: HuntSession(pid: pid, status: status), settings: AppSettings(), kb: kb, ai: ai, db: backend)
          ..addPhotos([File('assets/art/benny_idle.png').readAsBytesSync()]);

    test('分析后用 GPT 挑的形容词给怪兽起名；"完全不会"告诉生成修炼的任务', () async {
      final ai = FakeAi(missing: ['7A-2-02']);
      final c = make(ai, FakeDb(), status: '完全不会');
      await c.analyze();
      await settle();
      expect(c.session.monsterTraits.name, '慌张长角火红粗心鬼'.replaceFirst('粗心鬼', '糊涂虫'));
      expect(c.session.monsterTraits.intro, '它专偷负号。');
      expect(ai.received[1]['status'], '完全不会');
      expect(jsonEncode(c.session.summary()['monster']), contains('糊涂虫'));
    });

    Future<void> beatLesson(HuntController c) async {
      for (final a in ['8', '2', '2']) {
        c.submitTyped(a);
        c.nextQuestion();
      }
      c.submitTyped('C');
      await settle();
    }

    int found(FakeDb b) => b.events.where((e) => e.$1 == 'treasure.found').length;

    test('一只怪兽只有一件宝藏：修炼打完拿到；打赢 Boss、再打一遍、再订正都不再给', () async {
      final backend = FakeDb();
      final c = make(FakeAi(missing: ['7A-2-02']), backend);
      await c.analyze();
      await settle();
      c.startLearning();
      await beatLesson(c);
      expect(c.session.treasure?['id'], 'game-1/treasure');
      expect(c.session.treasure?['name'], '变号之剑');
      expect(c.session.treasure?['rarity'], 'legend', reason: '4 只都一次答对、没看提示');
      expect(found(backend), 1);
      expect((await PlayerStore.load()).treasures.length, 1);

      c.nextKp();
      c.submitBoss('2');
      await settle();
      expect(c.session.bossWon, isTrue);
      expect(found(backend), 1, reason: '打赢 Boss 不再掉宝藏');

      c.retryLesson();
      await beatLesson(c);
      c.retryBoss();
      c.submitBoss('2');
      await settle();
      expect(found(backend), 1, reason: '在怪兽屋里再打一遍也不给');
      expect((await PlayerStore.load()).treasures.length, 1);
    });

    test('要修炼好几个知识点的怪兽：全部打完才掉宝藏', () async {
      final backend = FakeDb();
      final c = make(FakeAi(missing: ['7A-1-04', '7A-2-02']), backend);
      await c.analyze();
      await settle();
      c.startLearning();
      await beatLesson(c);
      expect(c.session.treasure, isNull);
      expect(c.lessonsLeft, 1);
      c.nextKp();
      await beatLesson(c);
      expect(c.lessonsLeft, 0);
      expect(c.session.treasure, isNotNull);
      expect(found(backend), 1);
    });

    test('旧版本已经从这只怪兽拿过宝藏的，不再给', () async {
      await PlayerStore.add(Treasure(id: 'game-1/7A-2-02/r1', name: '旧宝藏', kind: '剑', material: '黄金', rarity: 'rare', stats: {'calc': 2}, value: 30, story: '', source: 'lesson'));
      final backend = FakeDb();
      final c = make(FakeAi(missing: ['7A-2-02']), backend);
      await c.analyze();
      await settle();
      c.startLearning();
      await beatLesson(c);
      expect(c.session.treasure, isNull);
      expect(found(backend), 0);
    });

    test('拍照订正：GPT 说全对但最终答案和标准答案对不上，App 不算对', () async {
      final c = make(
        FakeAi(missing: [], recheck: {'verdict': '全对', 'unreadable_reason': null, 'final_answer_seen': '7', 'first_error_step': null, 'error_type': '无错误', 'comment': '好'}),
        FakeDb(),
      );
      await c.analyze();
      c.goToBoss();
      c.redoPhotos.add([File('assets/art/benny_idle.png').readAsBytesSync()]);
      await c.submitRecheck();
      expect(c.session.recheck?['mismatch'], isTrue);
      expect(c.session.bossWon, isFalse);
      expect(c.redoPhotos.items, isEmpty, reason: '交过的照片清掉，改好再拍');
    });

    test('拍照订正做对了：算打赢 Boss', () async {
      final c = make(FakeAi(missing: []), FakeDb());
      await c.analyze();
      c.goToBoss();
      c.redoPhotos.add([File('assets/art/benny_idle.png').readAsBytesSync()]);
      await c.submitRecheck();
      await settle();
      expect(c.session.bossWon, isTrue);
      expect(c.session.treasure?['source'], 'boss', reason: '不用修炼的题，打赢 Boss 时掉宝藏');
      expect('${c.session.treasure?['name']}', contains('糊塗蟲'), reason: '界面是繁体中文');
    });
  });
}
