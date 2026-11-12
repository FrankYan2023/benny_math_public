import 'dart:typed_data';

import 'package:benny_math/game/game_data.dart';
import 'package:benny_math/i18n.dart';
import 'package:benny_math/logic/coach_controller.dart';
import 'package:benny_math/logic/hunt_controller.dart';
import 'package:benny_math/models/hunt.dart';
import 'package:benny_math/models/jail.dart';
import 'package:benny_math/models/knowledge.dart';
import 'package:benny_math/services/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));
final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff]);
const day = 24 * 3600 * 1000;

JailCase sample({int? since}) => JailCase(
      id: 'p1~boss', pid: 'p1', source: 'boss', problem: r'$-3-(-5)$', answerType: '数值', accepted: ['2'], correctAnswer: '2', since: since,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await GameData.load();
    i18n.setForTest(Lang.zh);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Knowledge kb;
  setUpAll(() async => kb = await Knowledge.load());
  final settings = AppSettings(); // 存档由 FakeDb 接住

  group('监狱规则（代码里定，不交给 GPT）', () {
    test('一步一步来：第 1 步讲给他看，后面每一步做对 / 做错 / 不会都往下走，全部做完才算学会', () {
      final c = sample()..coach = {'steps': [{}, {}, {}], 'final_answer': '2', 'idea': ''};
      c.startCoach();
      expect(c.at, 1);
      expect(c.log.single['how'], 'shown');
      c.finishStep('wrong', seen: '-3-5', where: '减号没变');
      expect(c.coachDone, isFalse);
      c.finishStep('right', seen: '2');
      expect(c.coachDone, isTrue);
      expect(c.stepsByHimself, 1);
      c.finishStep('right');
      expect(c.log.length, 3, reason: '做完了就不再记');
    });

    test('刑期：关进来的当天、同一天第二次都不算；在不同的两天里做对两次才放出来', () {
      final t0 = DateTime(2026, 10, 12, 10).millisecondsSinceEpoch;
      final c = sample(since: t0);
      expect(c.recordWin(t0 + 3600 * 1000), isFalse, reason: '关进来的当天不算');
      expect(c.recordWin(t0 + day), isTrue);
      expect(c.recordWin(t0 + day + 3600 * 1000), isFalse, reason: '同一天只算一次');
      expect(c.freed, isFalse);
      expect(c.recordWin(t0 + 2 * day), isTrue);
      expect(c.freed, isTrue);
      expect(c.summary()['wins'], hasLength(2));
    });

    test('又放弃一次：刑期从头算；放出来以后又不会了就重新关进来', () {
      final t0 = DateTime(2026, 10, 12, 10).millisecondsSinceEpoch;
      final c = sample(since: t0)..coach = {'steps': [{}, {}]};
      c.recordWin(t0 + day);
      c.gaveUpAgain(now: t0 + 2 * day);
      expect(c.wins, isEmpty);
      expect(c.fails, 2);
      expect(c.at, 1, reason: '步骤已经有了，直接重新一步一步来');
      c.recordWin(t0 + 3 * day);
      c.recordWin(t0 + 4 * day);
      expect(c.freed, isTrue);
      c.gaveUpAgain(now: t0 + 5 * day);
      expect(c.freed, isFalse);
      expect(c.since, t0 + 5 * day);
      expect(JailCase.fromJson(c.toJson()).toJson(), c.toJson());
    });
  });

  group('一步一步来（CoachController）', () {
    test('拆步骤只调用一次 GPT；每一步拍照检查一次；看不清不往下走；不会就直接讲', () async {
      final ai = FakeAi(stepVerdicts: ['看不清', '错']);
      final saved = <JailCase>[];
      final k = CoachController(c: sample(), ai: ai, save: saved.add);
      await k.start();
      expect(ai.calls, ['steps']);
      expect(k.c.at, 1);
      expect(k.canSubmit, isFalse, reason: '要先拍照');
      k.photos.add([jpeg]);
      await k.submitStep();
      expect(k.c.at, 1, reason: '看不清：重拍，不往下走');
      expect(k.lastCheck!['verdict'], '看不清');
      await k.submitStep();
      expect(k.c.at, 2);
      expect(k.c.log[1], containsPair('how', 'wrong'));
      expect(k.c.log[1]['where'], '减号没变');
      expect(k.photos.items, isEmpty, reason: '下一步重新拍');
      expect(ai.received.last['step'], 2);
      k.tellStep();
      expect(k.c.coachDone, isTrue);
      await k.start();
      expect(ai.calls.where((t) => t == 'steps'), hasLength(1), reason: '拆好的步骤存下来，不再调用');
      expect(saved.last.coachDone, isTrue);
    });

    test('提审：输入答案 App 比对；两次都错就重新一步一步来', () async {
      final t0 = DateTime.now().millisecondsSinceEpoch - 3 * day;
      final c = sample(since: t0)..coach = {'steps': [{}, {}]};
      c.startCoach();
      c.finishStep('right');
      final k = CoachController(c: c, ai: FakeAi(), save: (_) {});
      k.submitRetrial('3');
      expect(k.retrial!['final'], isFalse);
      k.submitRetrial('4');
      expect(k.retrial!['final'], isTrue);
      expect(c.coachDone, isFalse, reason: '没做对：再一步一步来一遍');
      expect(c.fails, 2);
      c.finishStep('right');
      k.submitRetrial('2');
      expect(k.retrial!['ok'], isTrue);
      expect(k.retrial!['counted'], isTrue);
      expect(c.wins, hasLength(1));
    });
  });

  group('打怪页面里放弃', () {
    HuntController make(FakeAi ai, FakeDb backend, {List<String> missing = const []}) =>
        HuntController(session: HuntSession(pid: 'pid-jail-1', status: '做错了'), settings: settings, kb: kb, ai: ai, db: backend)..addPhotos([jpeg]);

    test('放弃原题：Boss 算输，关进监狱，一步一步来；答案要等全部做完', () async {
      final ai = FakeAi(missing: []);
      final backend = FakeDb();
      final c = make(ai, backend);
      await c.analyze();
      c.goToBoss();
      expect(c.bossCoach, isNull);
      await c.giveUpBoss();
      expect(c.session.bossDone, isTrue);
      expect(c.session.bossWon, isFalse);
      expect(backend.events.map((e) => e.$1), contains('redo.checked'));
      final k = c.bossCoach!;
      expect(k.c.id, 'pid-jail-1~boss');
      expect(k.c.at, 1, reason: '第 1 步直接讲给他看');
      expect(k.c.monster, isNotNull);
      expect(backend.jail['pid-jail-1~boss'], isNotNull, reason: '后端监狱里有一份');
      expect(c.session.cases['pid-jail-1~boss'], isNotNull, reason: '打怪存档里也有一份');
      expect(ai.calls, ['analyze', 'steps']);
    });

    test('小怪答错两次：关进监狱（先不拆步骤），点"一步一步学会它"才调用 GPT；再放弃一次不再拆步骤', () async {
      final ai = FakeAi(missing: ['7A-2-02']);
      final backend = FakeDb();
      final c = make(ai, backend);
      await c.analyze();
      await settle();
      c.startLearning();
      c.submitTyped('1');
      c.submitTyped('1');
      await settle();
      final l = c.session.currentLesson!;
      final id = JailCase.practiceId('pid-jail-1', '7A-2-02', 0);
      expect(backend.jail[id], isNotNull);
      expect(c.practiceCoach(l, 0)!.c.hasSteps, isFalse);
      expect(ai.calls, isNot(contains('steps')));
      await c.coachPractice();
      expect(c.practiceCoach(l, 0)!.c.at, 1);
      expect(ai.calls.where((t) => t == 'steps'), hasLength(1));

      // 再打一遍，又放弃：刑期从头算，不再拆步骤
      c.retryLesson();
      c.openQuestion(0);
      await c.reveal();
      expect(c.practiceCoach(l, 0)!.c.fails, 2);
      expect(ai.calls.where((t) => t == 'steps'), hasLength(1));
    });

    test('关在监狱里的原题，以后再打 Boss 自己做对，也算一次刑期', () async {
      final backend = FakeDb();
      final c = make(FakeAi(missing: []), backend);
      await c.analyze();
      await c.giveUpBoss();
      final k = c.bossCoach!;
      k.tellStep();
      k.tellStep();
      expect(k.c.coachDone, isTrue);
      k.c.since -= 3 * day; // 假装是几天前关进来的
      c.retryBoss();
      c.submitBoss('2');
      expect(c.session.bossWon, isTrue);
      expect(k.c.wins, hasLength(1));
      expect(backend.jail[k.c.id]!['wins'], hasLength(1));
    });

    test('打开题目时把监狱里的新进度拿回来', () async {
      final backend = FakeDb();
      final c = make(FakeAi(missing: []), backend);
      await c.analyze();
      await c.giveUpBoss();
      final fresh = c.bossCoach!.c.copy()..wins = [123];
      backend.jail[fresh.id] = fresh.toJson();
      await c.refreshCases();
      expect(c.bossCoach!.c.wins, [123]);
    });
  });
}
