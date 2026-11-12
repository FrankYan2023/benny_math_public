import 'dart:convert';
import 'dart:typed_data';

import 'dart:io';

import 'package:benny_math/logic/hunt_controller.dart';
import 'package:benny_math/logic/photo_hash.dart';
import 'package:benny_math/services/local_db.dart';
import 'package:benny_math/models/hunt.dart';
import 'package:benny_math/models/knowledge.dart';
import 'package:benny_math/services/settings.dart';
import 'package:benny_math/game/game_data.dart';
import 'package:benny_math/i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));
final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await GameData.load();
    i18n.setForTest(Lang.zh);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Knowledge kb;
  setUpAll(() async => kb = await Knowledge.load());

  HuntController make(FakeAi ai, FakeDb backend, {String pid = 'test-pid-1'}) =>
      HuntController(session: HuntSession(pid: pid, status: '做错了'), settings: AppSettings(), kb: kb, ai: ai, db: backend);

  test('完整流程只调用两次 GPT：分析 + 一次生成全部修炼；练习和 Boss 都由 App 比对；上报事件', () async {
    final ai = FakeAi();
    final backend = FakeDb();
    final c = make(ai, backend)..addPhotos([jpeg, jpeg]);

    await c.analyze();
    expect(c.session.stage, 'analysis');
    expect(c.session.queue, ['7A-1-04', '7A-2-02']);
    await settle();
    expect(ai.calls, ['analyze', 'training'], reason: '分析完就在后台一次生成全部修炼内容');
    expect(c.session.trainingReady, isTrue);

    c.startLearning();
    for (final _ in c.session.queue) {
      final l = c.session.currentLesson!;
      c.setTab('practice');
      c.submitTyped('8');
      c.nextQuestion();
      c.submitTyped('3'); // 错一次
      expect(l.results[1]!.done, isFalse, reason: '每题有两次机会');
      c.submitTyped('2');
      c.nextQuestion();
      c.hint();
      c.submitTyped('2');
      c.nextQuestion();
      c.submitTyped('C');
      expect(l.finished, isTrue);
      expect(l.score().passed, isTrue);
      c.submitTyped('A');
      expect(l.results[3]!.correct, isTrue, reason: '打完的小怪不能再打');
      c.nextKp();
    }
    expect(c.session.stage, 'boss');
    c.submitBoss('2');
    expect(c.session.bossWon, isTrue);
    c.finish();
    expect(c.session.stage, 'victory');
    expect(ai.calls, ['analyze', 'training'], reason: '整个过程只调用两次 GPT');

    final types = backend.events.map((e) => e.$1).toList();
    expect(types.where((t) => t == 'problem.analyzed').length, 1);
    expect(types.where((t) => t == 'practice.graded').length, 8);
    expect(types.where((t) => t == 'lesson.finished').length, 2);
    expect(types.where((t) => t == 'redo.checked').length, 1);
    expect(backend.events.firstWhere((e) => e.$1 == 'redo.checked').$2['isCorrect'], isTrue);
    c.dispose();
    await settle();
    expect(backend.saved['test-pid-1']?['stage'], 'victory', reason: '关掉时把存档存到后端');
  });

  test('从存档打开：修炼内容已经有了，不再调用 GPT', () async {
    final ai = FakeAi();
    final backend = FakeDb();
    final c = make(ai, backend)..addPhotos([jpeg]);
    await c.analyze();
    await settle();
    c.dispose();
    await settle();

    final restored = HuntSession.fromJson(jsonDecode(jsonEncode(backend.saved['test-pid-1'])) as Map<String, dynamic>);
    final ai2 = FakeAi();
    final c2 = HuntController(session: restored, settings: AppSettings(), kb: kb, ai: ai2, db: FakeDb());
    expect(restored.trainingReady, isTrue);
    c2.startLearning();
    await c2.loadTraining();
    expect(ai2.calls, isEmpty);
    expect(c2.session.currentLesson!.practice.length, 4);
  });

  test('讲解、例题、打小怪可以随时切换，切回来进度还在', () async {
    final c = make(FakeAi(missing: ['7A-2-02']), FakeDb())..addPhotos([jpeg]);
    await c.analyze();
    await settle();
    c.startLearning();
    final l = c.session.currentLesson!;
    c.setTab('practice');
    c.submitTyped('8');
    c.setTab('card');
    c.setTab('example');
    c.nextExampleStep();
    c.setTab('practice');
    expect(l.results[0]!.correct, isTrue);
    expect(l.exStep, 2);
    c.openQuestion(3);
    expect(l.q, 3);
  });

  test('答错两次给出答案；原题没法自动比对时自己对照判断', () async {
    final c = make(FakeAi(missing: [], answerType: '其他'), FakeDb())..addPhotos([jpeg]);
    await c.analyze();
    expect(c.session.bossCheckable, isFalse);
    c.goToBoss();
    c.selfCheckBoss(false);
    expect(c.session.bossDone, isTrue);
    expect(c.session.bossWon, isFalse);

    final c2 = make(FakeAi(missing: ['7A-2-02']), FakeDb(), pid: 'test-pid-2')..addPhotos([jpeg]);
    await c2.analyze();
    await settle();
    c2.startLearning();
    c2.submitTyped('1');
    c2.submitTyped('2');
    final r = c2.session.currentLesson!.results[0]!;
    expect(r.revealed, isTrue);
    expect(r.counted, isFalse);
  });

  test('村庄修炼：第一次进去调用一次 GPT（没有原题），存进村庄存档；再进来直接读存档', () async {
    SharedPreferences.setMockInitialValues({});
    final unfinished = HuntSession(pid: 'still-here', status: '做错了');
    await SessionStore.save(unfinished);

    final ai = FakeAi();
    final backend = FakeDb();
    final c = HuntController(session: HuntSession.village('7A-3-02'), settings: AppSettings(), kb: kb, ai: ai, db: backend);
    await c.waitForTraining();
    expect(ai.calls, ['training']);
    expect(ai.received.single['problemText'], '', reason: '村庄修炼没有原题');
    expect([for (final k in ai.received.single['kps'] as List) (k as Map)['kpId']], ['7A-3-02']);
    expect(c.session.stage, 'learn');

    c.setTab('practice');
    c.submitTyped('8');
    c.nextKp(); // 村庄修炼没有 Boss 战
    expect(c.session.stage, 'learn');
    c.dispose();
    await settle();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(backend.villages['7A-3-02'], isNotNull, reason: '存进村庄存档');
    expect(backend.saved, isEmpty, reason: '不进错题的打怪存档');
    expect((await SessionStore.load())?.pid, 'still-here', reason: '不覆盖本机"上次没打完的错题"');
    expect(backend.events.first.$2['pid'], 'village-7A-3-02');

    final restored = HuntSession.fromJson(jsonDecode(jsonEncode(backend.villages['7A-3-02'])) as Map<String, dynamic>);
    final ai2 = FakeAi();
    final c2 = HuntController(session: restored, settings: AppSettings(), kb: kb, ai: ai2, db: FakeDb());
    await c2.waitForTraining();
    expect(ai2.calls, isEmpty, reason: '存档里已经有修炼内容');
    expect(c2.session.currentLesson!.results[0]!.correct, isTrue, reason: '进度也保存了');
    expect(restored.isVillage, isTrue);
  });

  test('照片指纹：同一张照片一样，不同照片差很多', () async {
    final a = File('assets/art/worldmap.png').readAsBytesSync();
    final b = File('assets/art/benny_idle.png').readAsBytesSync();
    final ha = await photoHash(a), ha2 = await photoHash(Uint8List.fromList(a)), hb = await photoHash(b);
    expect(ha, isNotNull);
    expect(ha!.length, 64);
    expect(ha2, ha);
    expect(hashDistance(ha, hb!), greaterThan(30));
    expect(samePhotos([hb, ha], [ha]), isTrue);
    expect(await photoHash(Uint8List.fromList([1, 2, 3])), isNull, reason: '不是图片就没有指纹');
  });

  test('拍过的题：认出来就不调用 GPT，问一下是不是这道；说不是就照常分析，分析结果带上指纹', () async {
    final photo = File('assets/art/worldmap.png').readAsBytesSync();
    final hash = (await photoHash(photo))!;
    final backend = FakeDb()
      ..archive.add(HuntSummary.fromJson({
        'pid': 'old-hunt-1', 'createdAt': 1, 'updatedAt': 2, 'problemText': r'计算：$-3-(-5)$', 'stage': 'victory',
        'kpIds': ['7A-2-02'], 'errorType': '概念不清', 'photoHashes': [hash], 'done': true,
      }));
    final ai = FakeAi();
    final c = HuntController(
      session: HuntSession(pid: 'new-hunt', status: '做错了'),
      settings: AppSettings(),
      kb: kb,
      ai: ai,
      db: backend,
    )..addPhotos([photo]);
    await c.analyze();
    expect(c.seenBefore?.pid, 'old-hunt-1');
    expect(ai.calls, isEmpty, reason: '认出是拍过的题，没有调用 GPT');
    expect(c.session.stage, 'capture');

    await c.analyzeAnyway();
    expect(ai.calls.first, 'analyze');
    expect(c.session.photoHashes, [hash], reason: '存档里记下指纹，下次能认出来');
    expect(c.session.summary()['photoHashes'], [hash]);
  });

  test('修炼可以用同样的题再打一遍，记成第 2 遍', () async {
    final backend = FakeDb();
    final fakeAi = FakeAi(missing: ['7A-2-02']);
    final c = make(fakeAi, backend)..addPhotos([jpeg]);
    await c.analyze();
    await settle();
    c.startLearning();
    final l = c.session.currentLesson!;
    for (final a in ['8', '2', '2']) {
      c.submitTyped(a);
      c.nextQuestion();
    }
    c.submitTyped('C');
    expect(l.finished, isTrue);
    c.retryLesson();
    expect(l.finished, isFalse);
    expect(l.round, 2);
    expect(l.tab, 'practice');
    c.submitTyped('8');
    expect(backend.events.last.$2['round'], 2);
    expect(fakeAi.calls, ['analyze', 'training'], reason: '再打一遍不调用 GPT');
  });

  test('照片指纹没认出来时，把做过的题目一起发给 GPT；GPT 认出是同一道，就问"是不是这道"', () async {
    final backend = FakeDb()
      ..archive.add(HuntSummary.fromJson({
        'pid': 'old-hunt-2', 'createdAt': 1, 'updatedAt': 2, 'problemText': r'计算：$-3-(-5)$', 'stage': 'learn',
        'kpIds': ['7A-2-02'], 'errorType': '概念不清', 'photoHashes': <String>[], 'done': false,
      }));
    final ai = FakeAi(duplicateOf: 'P1');
    final c = HuntController(
      session: HuntSession(pid: 'new-hunt-2', status: '做错了'),
      settings: AppSettings(),
      kb: kb,
      ai: ai,
      db: backend,
    )..addPhotos([File('assets/art/benny_idle.png').readAsBytesSync()]);
    await c.analyze();
    expect(ai.calls, ['analyze'], reason: '只调用一次，GPT 很快回答"是做过的题"');
    expect(ai.received.single['knownProblems'], [
      {'id': 'P1', 'text': r'计算：$-3-(-5)$'},
    ]);
    expect(c.seenBefore?.pid, 'old-hunt-2');
    expect(c.session.stage, 'capture', reason: '不当成新题保存');
    expect(backend.events, isEmpty, reason: '不上报');
  });
}
