import 'dart:convert';
import 'dart:io';

import 'package:benny_math/game/game_data.dart';
import 'package:benny_math/models/hunt.dart';
import 'package:benny_math/logic/report.dart';
import 'package:benny_math/models/jail.dart';
import 'package:benny_math/models/knowledge.dart';
import 'package:benny_math/services/local_db.dart';
import 'package:benny_math/theme/pixel_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机数据库：真的写文件，重新打开还在；掌握状态规则和原来后端的一样
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(GameData.load);
  late Directory dir;
  LocalDb fresh() => LocalDb(dir); // 新开一个实例 = 重新打开 App

  setUp(() => dir = Directory.systemTemp.createTempSync('benny-db-'));
  tearDown(() => dir.deleteSync(recursive: true));

  HuntSession hunt(String pid, {String stage = 'learn'}) => HuntSession(pid: pid, stage: stage, analysis: {
        'readable': true, 'problem_text': '计算：-3-(-5)', 'error': {'type': '概念不清'}, 'knowledge_points': [],
      }, queue: ['7A-2-02']);

  test('打怪存档：保存、列表（最近的在前）、读回、放生；重新打开还在', () async {
    final db = fresh();
    await db.saveHunt(hunt('p-0001'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await db.saveHunt(hunt('p-0002', stage: 'victory'));
    final again = fresh();
    final list = await again.listHunts();
    expect(list.map((h) => h.pid), ['p-0002', 'p-0001']);
    expect(list.first.done, isTrue);
    expect(list.first.kpIds, ['7A-2-02']);
    expect((await again.getHunt('p-0001')).problemText, '计算：-3-(-5)');

    final createdAt = list.last.createdAt;
    await again.saveHunt(hunt('p-0001'));
    expect((await fresh().listHunts()).firstWhere((h) => h.pid == 'p-0001').createdAt, createdAt, reason: '第一次保存的时间不变');

    await again.deleteHunt('p-0001');
    expect((await fresh().listHunts()).map((h) => h.pid), ['p-0002']);
    expect(() => fresh().getHunt('p-0001'), throwsA(isA<LocalDbException>()));
  });

  test('示例模式的存档不保存', () async {
    await fresh().saveHunt(HuntSession(pid: 'demo-1', demo: true, analysis: {'readable': true}));
    expect(await fresh().listHunts(), isEmpty);
  });

  test('村庄修炼存档和怪兽监狱', () async {
    final db = fresh();
    final v = HuntSession.village('7A-2-02');
    await db.saveVillage(v);
    expect(await fresh().getVillage('7A-2-02'), isNotNull);
    expect(await fresh().getVillage('7A-1-01'), isNull);
    expect((await fresh().listVillages()).keys, ['7A-2-02']);

    final c = JailCase(id: 'p9~boss', pid: 'p9', source: 'boss', problem: 'x', answerType: '数值', accepted: ['2'], correctAnswer: '2', since: 1);
    await db.saveJail(c);
    expect((await fresh().getJail('p9~boss'))?.pid, 'p9');
    expect(await fresh().listJail(), hasLength(1));
    expect(await fresh().jailSummaries(), hasLength(1));
  });

  test('学习事件：分析判为薄弱 → 练习过关变学习中；题目记录和每日统计', () async {
    final db = fresh();
    await db.record('problem.analyzed', {
      'pid': 'p-0001', 'problemText': 'x', 'isCorrect': false, 'correctAnswer': '2', 'studentAnswer': '-8',
      'error': {'step': 1, 'type': '概念不清', 'description': ''},
      'knowledgePoints': [{'kpId': '7A-2-02', 'role': '主', 'judgement': '不会'}, {'kpId': '7A-1-01', 'role': '辅', 'judgement': '会'}],
      'missingKps': ['7A-2-02'],
    });
    var states = await fresh().kpStates();
    expect(states['7A-2-02']?.status, KpStatus.weak);
    expect(states['7A-1-01']?.status, KpStatus.basic);

    await db.record('practice.graded', {'pid': 'p-0001', 'kpId': '7A-2-02', 'correct': true, 'revealed': false, 'skipped': false});
    await db.record('lesson.finished', {'pid': 'p-0001', 'kpId': '7A-2-02', 'round': 1, 'right': 4, 'total': 4, 'passed': true});
    await db.record('session.ended', {'seconds': 600});
    final again = fresh();
    states = await again.kpStates();
    expect(states['7A-2-02']?.status, KpStatus.learning);

    final p = (await again.problems())['p-0001'] as Map;
    expect((p['lessons'] as Map)['7A-2-02'], {'rounds': 1, 'passed': true, 'right': 4, 'total': 4});
    final today = (await again.daily()).values.single as Map;
    expect(today, {'problems': 1, 'firstTryCorrect': 0, 'practice': 1, 'practiceRight': 1, 'lessons': 1, 'lessonsPassed': 1, 'seconds': 600});
    expect(File('${dir.path}/events.jsonl').readAsLinesSync(), hasLength(4));

    await db.record('lesson.finished', {'pid': 'p-0001', 'kpId': '7A-2-02', 'round': 2, 'right': 1, 'total': 4, 'passed': false});
    expect((await fresh().kpStates())['7A-2-02']?.status, KpStatus.weak, reason: '没过关又变回薄弱');
  });

  test('家长报表：题目、错因、监狱、时长都从本机数据算出来', () async {
    final kb = await Knowledge.load();
    final db = fresh();
    Future<void> analyzed(String pid, String type, {bool? correct}) => db.record('problem.analyzed', {
          'pid': pid, 'problemText': '题 $pid', 'isCorrect': correct, 'correctAnswer': '2', 'studentAnswer': null,
          'error': {'step': null, 'type': type, 'description': '错在第一步'},
          'knowledgePoints': [], 'missingKps': ['7A-2-02'],
        });
    await analyzed('p-1', '计算失误', correct: false);
    await analyzed('p-2', '计算失误', correct: false);
    await analyzed('p-3', '无错误', correct: true);
    await db.record('lesson.finished', {'pid': 'p-1', 'kpId': '7A-2-02', 'round': 1, 'right': 3, 'total': 4, 'passed': true});
    await db.record('session.ended', {'seconds': 1800});
    await db.saveJail(JailCase(id: 'p-2~boss', pid: 'p-2', source: 'boss', problem: '题 p-2', answerType: '数值', accepted: ['2'], correctAnswer: '2', since: 5));

    final now = DateTime.now().millisecondsSinceEpoch;
    final r = await ParentReport.build(fresh(), kb, from: now - 3600 * 1000, to: now + 1000);
    expect(r.summary.problems, 3);
    expect(r.summary.firstTryCorrect, 1);
    expect(r.summary.lessonsPassed, 1);
    expect(r.summary.minutes, 30);
    expect(r.summary.activeDays, 1);
    expect(r.problems, hasLength(3));
    expect(r.problems.firstWhere((p) => p.pid == 'p-1').lessons['7A-2-02']?.passed, isTrue);
    expect(r.problems.firstWhere((p) => p.pid == 'p-3').redo, '不用重做');
    expect(r.errorTypes, [('计算失误', 2)]);
    expect(r.jailLocked, 1);
    expect(r.attention, isEmpty, reason: '练习过关后是学习中，不再算薄弱');
    expect(r.kpStatus['7A-2-02'], KpStatus.learning);
  });

  test('备份和恢复：导出一个 JSON，在另一台设备上恢复，存档、知识点状态、宝藏、名字都回来', () async {
    SharedPreferences.setMockInitialValues({'studentName': 'Benny', 'player.treasures.v1': '[{"id":"t1"}]', 'chatgpt.model.chosen': 'x'});
    final db = fresh();
    await db.saveHunt(hunt('p-0001'));
    await db.record('lesson.finished', {'pid': 'p-0001', 'kpId': '7A-2-02', 'round': 1, 'right': 4, 'total': 4, 'passed': true});
    final backup = await db.exportAll();
    expect((backup['prefs'] as Map).keys, unorderedEquals(['studentName', 'player.treasures.v1']), reason: '不带 ChatGPT 的设置');

    // 另一台设备：原来有别的数据，恢复后全换成备份里的
    final other = Directory.systemTemp.createTempSync('benny-db-');
    addTearDown(() => other.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({'studentName': 'Someone'});
    final db2 = LocalDb(other);
    await db2.saveHunt(hunt('p-9999'));
    await db2.importAll(jsonDecode(jsonEncode(backup)) as Map<String, dynamic>);
    final again = LocalDb(other);
    expect((await again.listHunts()).map((h) => h.pid), ['p-0001']);
    expect((await again.kpStates())['7A-2-02']?.status, KpStatus.learning);
    expect(File('${other.path}/events.jsonl').readAsLinesSync(), hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('studentName'), 'Benny');
    expect(prefs.getString('player.treasures.v1'), '[{"id":"t1"}]');

    expect(() => db2.importAll({'app': 'other'}), throwsA(isA<LocalDbException>()));
    expect(() => db2.importAll({'app': 'benny-math', 'format': 1, 'files': {'../evil.json': {}}}), throwsA(isA<LocalDbException>()));
  });

  test('家庭版没传上后端的学习事件：升级后按时间顺序收进本机，再删掉队列', () async {
    SharedPreferences.setMockInitialValues({
      'pendingEvents': [
        jsonEncode({'type': 'lesson.finished', 'eid': 'e2', 'at': 2000, 'pid': 'p-1', 'kpId': '7A-2-02', 'round': 1, 'right': 4, 'total': 4, 'passed': true}),
        jsonEncode({'type': 'problem.analyzed', 'eid': 'e1', 'at': 1000, 'pid': 'p-1', 'problemText': 'x', 'isCorrect': false, 'correctAnswer': '2', 'studentAnswer': null,
          'error': {'step': 1, 'type': '概念不清', 'description': ''}, 'knowledgePoints': [], 'missingKps': ['7A-2-02']}),
        'not json',
      ],
    });
    final db = fresh();
    expect(await db.ingestLegacyQueue(), 2);
    expect((await fresh().kpStates())['7A-2-02']?.status, KpStatus.learning, reason: '先分析（薄弱）再过关（学习中），按时间顺序');
    expect(((await fresh().problems())['p-1'] as Map)['lessons'], isNotEmpty);
    expect((await SharedPreferences.getInstance()).getStringList('pendingEvents'), isNull);
    expect(await db.ingestLegacyQueue(), 0, reason: '只收一次');
  });
}
