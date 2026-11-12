import 'dart:convert';

import 'package:benny_math/ai/ai_service.dart';
import 'package:benny_math/ai/ai_tasks.dart';
import 'package:benny_math/ai/ai_usage.dart';
import 'package:benny_math/ai/chatgpt_auth.dart';
import 'package:benny_math/ai/direct_ai.dart';
import 'package:benny_math/ai/responses_client.dart';
import 'package:benny_math/models/knowledge.dart';
import 'package:flutter/services.dart';
import 'package:benny_math/game/game_data.dart';
import 'package:benny_math/i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const img = 'data:image/jpeg;base64,AAAA';

/// 假的 Responses 接口：按顺序返回准备好的回答，记下每次请求
class FakeResponses extends ResponsesClient {
  FakeResponses(this.replies) : super(ChatGptAuth());
  final List<String> replies;
  final requests = <Map<String, dynamic>>[];

  @override
  Future<List<String>> listModels() async => models;
  List<String> models = ['gpt-test-1', 'gpt-test-2'];

  @override
  Future<AiReply> respond({
    required String model,
    required String instructions,
    required List<Map<String, dynamic>> input,
    required String schemaName,
    required Map<String, dynamic> schema,
    String effort = ResponsesClient.reasoningEffort,
    CancelToken? token,
  }) async {
    requests.add({'model': model, 'effort': effort, 'instructions': instructions, 'input': input, 'schemaName': schemaName, 'schema': schema});
    final r = replies.removeAt(0);
    if (r == 'QUOTA') throw ResponsesClient.mapError('subscription_sharing_usage_limit_exceeded', null);
    return AiReply(r, input: 1000, output: 200);
  }
}

Stream<String> sse(List<Map<String, dynamic>> events) =>
    Stream.fromIterable([for (final e in events) 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n']);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await GameData.load();
    i18n.setForTest(Lang.zh);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Knowledge kb;
  late AiTasks tasks;
  late Map<String, dynamic> demo;
  setUpAll(() async {
    kb = await Knowledge.load();
    tasks = await AiTasks.load(kb);
    demo = jsonDecode(await rootBundle.loadString('assets/demo.json')) as Map<String, dynamic>;
  });

  group('提示词和输出格式', () {
    test('提示词从共享文件读取，占位符都替换掉了，\$\$ 没有被吞掉', () {
      final p = tasks.prepare('analyze', {'images': [img], 'status': '做错了'});
      expect(p.instructions, contains('学生叫 Benny'), reason: '没给名字时用 Benny');
      expect(p.instructions, contains(r'不要用 $$'));
      expect(p.instructions, isNot(contains('{{')));
      final many = tasks.prepare('analyze', {'images': [img, img, img], 'status': '做错了'});
      final parts = (many.input.single['content'] as List).cast<Map>();
      expect(parts.where((c) => c['type'] == 'input_image').length, 3, reason: '几张照片按顺序都发给 GPT');
      expect(parts.map((c) => c['text']).whereType<String>().join(), contains('第 3 张'));
      final enumIds = ((((p.schema['properties'] as Map)['missing_kps'] as Map)['items'] as Map)['properties'] as Map)['kp_id']['enum'] as List;
      expect(enumIds.length, 122, reason: '知识点编号用枚举限定在清单里');
    });

    test('输入参数不对时直接报错，不去调用 AI', () {
      expect(() => tasks.prepare('analyze', {'status': '做错了'}), throwsA(isA<AiException>()));
      expect(() => tasks.prepare('analyze', {'images': List.filled(7, img), 'status': '做错了'}), throwsA(isA<AiException>()));
      expect(() => tasks.prepare('analyze', {'images': [img, 'data:text/plain;base64,AAAA'], 'status': '做错了'}), throwsA(isA<AiException>()));
      expect(() => tasks.prepare('training', {'kps': [{'kpId': '9Z-9-99'}]}), throwsA(isA<AiException>()));
      expect(() => tasks.prepare('lesson', {'kpId': '7A-2-02'}), throwsA(isA<AiException>()), reason: '旧任务已经去掉');
      expect(() => tasks.prepare('nope', {}), throwsA(isA<AiException>()));
    });

    test('示例数据通过所有校验', () {
      final a = Map.of(demo['analysis'] as Map<String, dynamic>);
      expect(tasks.prepare('analyze', {'images': [img], 'status': '做错了'}).validate(a), isEmpty);
      final kps = [for (final m in a['missing_kps'] as List) {'kpId': (m as Map)['kp_id'], 'reason': m['reason']}];
      final training = jsonDecode(jsonEncode(demo['training'])) as Map<String, dynamic>;
      expect(tasks.prepare('training', {'problemText': a['problem_text'], 'kps': kps}).validate(training), isEmpty);
      for (final l in training['lessons'] as List) {
        expect(((l as Map)['card'] as Map)['visual'], isNotNull, reason: '示例图示应该保留');
      }
    });

    test('修炼内容：知识点要按顺序一个不少，每个正好 4 道题', () {
      final kps = [{'kpId': '7A-1-04', 'reason': ''}, {'kpId': '7A-2-02', 'reason': ''}];
      final p = tasks.prepare('training', {'problemText': '计算', 'kps': kps});
      final lessons = (jsonDecode(jsonEncode(demo['training'])) as Map)['lessons'] as List;
      expect(p.validate({'lessons': [lessons[1], lessons[0]]}), isNotEmpty, reason: '顺序反了');
      expect(p.validate({'lessons': [lessons[0]]}), isNotEmpty, reason: '少了一个');
      final short = jsonDecode(jsonEncode(lessons[0])) as Map<String, dynamic>;
      (short['practice'] as List).removeLast();
      expect(p.validate({'lessons': [short, lessons[1]]}).join(), contains('正好 4 道题'));
    });

    test('做过的题目清单：只接受 P 加数字的编号；GPT 认出是同一道时其余字段不用填', () {
      final p = tasks.prepare('analyze', {
        'images': [img],
        'status': '做错了',
        'knownProblems': [
          {'id': 'P1', 'text': '计算：x+1'},
          {'id': 'X9', 'text': '坏编号'},
          {'id': 'P2', 'text': ''},
        ],
      });
      final texts = [for (final c in p.input.single['content'] as List) (c as Map)['text']].whereType<String>().join();
      expect(texts, contains('P1 | 计算：x+1'));
      expect(texts, isNot(contains('坏编号')));
      expect(jsonEncode((p.schema['properties'] as Map)['duplicate_of']), contains('"P1"'));
      expect(p.validate({'readable': true, 'duplicate_of': 'P1'}), isEmpty);
      expect(p.validate({'readable': true, 'duplicate_of': 'P7'}), isNotEmpty);
      final plain = tasks.prepare('analyze', {'images': [img], 'status': '做错了'});
      expect((plain.schema['properties'] as Map)['duplicate_of'], {'type': 'null'}, reason: '没有做过的题时只能是 null');
    });

    test('写给学生的文字用界面的语言；分析要给怪兽挑形容词，修炼要给宝藏，订正只看解答照片', () {
      final zh = tasks.prepare('analyze', {'images': [img], 'status': '做错了', 'lang': 'zh'});
      final en = tasks.prepare('analyze', {'images': [img], 'status': '做错了', 'lang': 'en'});
      final es = tasks.prepare('analyze', {'images': [img], 'status': '做错了', 'lang': 'es', 'student': 'Lucía'});
      expect(zh.instructions, contains('都用繁体中文'));
      expect(en.instructions, contains('都用简单的英文'));
      expect(es.instructions, contains('都用简单的西班牙语'));
      expect(es.instructions, contains('学生叫 Lucía'), reason: '用设置里填的名字');
      expect(en.instructions, isNot(contains('{{')));
      expect(es.instructions, isNot(contains('{{')));
      expect(((zh.schema['properties'] as Map)['monster'] as Map)['properties'], contains('personality'));
      final t = tasks.prepare('training', {'problemText': '计算', 'status': '完全不会', 'kps': [{'kpId': '7A-2-02', 'reason': ''}]});
      expect(jsonEncode(t.input), contains('原题完全不会做'));
      final lesson = ((t.schema['properties'] as Map)['lessons'] as Map)['items'] as Map;
      expect((lesson['properties'] as Map).keys, contains('treasure'));
      final r = tasks.prepare('recheck', {'images': [img], 'problemText': '计算', 'correctAnswer': '2', 'solutionSteps': ['2']});
      expect(r.instructions, contains('照片里只有学生写的解答'));
      expect(r.validate({'verdict': '全对', 'unreadable_reason': null, 'final_answer_seen': '2', 'first_error_step': 2, 'error_type': '无错误', 'comment': '好'}), isNotEmpty);
      expect(r.validate({'verdict': '看不清', 'unreadable_reason': '太暗', 'final_answer_seen': null, 'first_error_step': null, 'error_type': '未作答', 'comment': ''}), isEmpty);
    });

    test('一步一步来：拆步骤不能在目标和提示里写出结果；检查一步只看这一步', () {
      final st = tasks.prepare('steps', {'problemText': r'计算：$-3-(-5)+|-2|$', 'correctAnswer': '4', 'solutionSteps': ['-3+5+2', '=4'], 'lang': 'zh'});
      expect(st.instructions, contains('不能写出这一步的结果'));
      expect(st.validate((demo['steps'] as Map).cast<String, dynamic>()), isEmpty, reason: '示例数据要能通过校验');
      final leak = jsonDecode(jsonEncode(demo['steps'])) as Map<String, dynamic>;
      ((leak['steps'] as List)[1] as Map)['hint'] = r'写成 $-3+5$ 就行';
      expect(st.validate(leak), isNotEmpty);
      expect(st.validate({'steps': [], 'final_answer': '', 'idea': ''}), isNotEmpty);
      expect(() => tasks.prepare('steps', {'problemText': ''}), throwsA(isA<AiException>()));

      final steps = [for (final s in (demo['steps'] as Map)['steps'] as List) {'goal': (s as Map)['goal'], 'result': s['result']}];
      final ck = tasks.prepare('stepcheck', {'images': [img], 'problemText': '计算', 'steps': steps, 'step': 2});
      final text = jsonEncode(ck.input);
      expect(text, contains('这一步（第 2 步）'));
      expect(text, contains('1. '), reason: '前面完成的步骤也带上');
      expect(ck.validate({'verdict': '错', 'seen': '-3-5', 'where': '', 'comment': '加油'}), isNotEmpty, reason: '错了要说明错在哪里');
      expect(ck.validate({'verdict': '对', 'seen': '-3+5', 'where': '', 'comment': '好'}), isEmpty);
      expect(ck.validate({'verdict': '看不清', 'seen': null, 'where': '太暗了', 'comment': ''}), isEmpty);
      expect(() => tasks.prepare('stepcheck', {'images': [img], 'problemText': '计算', 'steps': steps, 'step': 9}), throwsA(isA<AiException>()));
    });

    test('原题答案：选择题只能写字母，"其他"类型可以没有答案', () {
      final p = tasks.prepare('analyze', {'images': [img], 'status': '做错了'});
      final a = Map.of(demo['analysis'] as Map<String, dynamic>);
      expect(p.validate({...a, 'answer_type': '选择', 'accepted_answers': ['4']}), isNotEmpty);
      expect(p.validate({...a, 'answer_type': '数值', 'accepted_answers': []}), isNotEmpty);
      expect(p.validate({...a, 'answer_type': '其他', 'accepted_answers': []}), isEmpty);
    });

    test('图示数据不合格就去掉，不影响讲解', () {
      expect(visualProblem({'kind': 'number_line', 'min': -5, 'max': 5, 'step': 1, 'points': [{'value': 9, 'label': '9', 'highlight': true}], 'jumps': [], 'spans': []}),
          '有数值超出数轴范围');
      expect(visualProblem({'kind': 'expr_steps', 'steps': [{'latex': 'a', 'note': ''}]}), '算式步骤数量不对');
      expect(visualProblem(null), '');
    });
  });

  group('Responses 事件流', () {
    test('收到 completed 才算成功，取 output_text', () async {
      final text = await ResponsesClient.readStream(sse([
        {'type': 'response.output_text.delta', 'delta': '{"a"'},
        {
          'type': 'response.completed',
          'response': {
            'output': [
              {'type': 'message', 'content': [{'type': 'output_text', 'text': '{"a":1}'}]},
            ],
          },
        },
      ]));
      expect(text, '{"a":1}');
    });

    test('额度用完、没写完、中途断开都报对应的错', () async {
      await expectLater(
        ResponsesClient.readStream(sse([
          {'type': 'response.failed', 'response': {'error': {'code': 'subscription_sharing_usage_limit_exceeded', 'message': 'x'}}},
        ])),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'quota')),
      );
      await expectLater(
        ResponsesClient.readStream(sse([
          {'type': 'response.incomplete', 'response': {'incomplete_details': {'reason': 'max_output_tokens'}}},
        ])),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'incomplete')),
      );
      await expectLater(
        ResponsesClient.readStream(sse([{'type': 'response.output_text.delta', 'delta': '{'}])),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'interrupted')),
      );
    });
  });

  group('iPad 直连', () {
    final kps = [{'kpId': '7A-1-04', 'reason': ''}, {'kpId': '7A-2-02', 'reason': ''}];

    test('输出不合格时带着问题让 GPT 改，改好就返回；默认用快模型、低思考强度', () async {
      final lessons = (demo['training'] as Map)['lessons'] as List;
      final bad = jsonEncode({'lessons': [lessons[0]]}); // 少了第 2 个知识点
      final good = jsonEncode({'lessons': lessons});
      final fake = FakeResponses([bad, good])..models = ['gpt-6-astra', ResponsesClient.preferredModel, 'gpt-5.5'];
      final ai = DirectAi(kb: kb, client: fake);
      final r = await ai.task('training', {'problemText': '计算', 'kps': kps});
      expect((r['lessons'] as List).length, 2);
      expect(fake.requests.length, 2);
      expect(fake.requests.first['model'], ResponsesClient.preferredModel, reason: '账号里有快模型就默认用它');
      expect(fake.requests.first['effort'], 'low');
      final retryInput = fake.requests[1]['input'] as List;
      expect(jsonEncode(retryInput.last), contains('你上一次的输出有这些问题'));
    });

    test('账号里没有快模型就用推荐顺序的第一个；手动选过就用选的', () async {
      final fake = FakeResponses([]);
      final ai = DirectAi(kb: kb, client: fake);
      expect(await ai.model(), 'gpt-test-1');
      await DirectAi.setModel('gpt-test-2');
      expect(await ai.model(), 'gpt-test-2');
    });

    test('连续 3 次不合格就报错', () async {
      final bad = jsonEncode({'lessons': []});
      final ai = DirectAi(kb: kb, client: FakeResponses([bad, bad, bad]));
      await expectLater(
        ai.task('training', {'problemText': '计算', 'kps': kps}),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'invalid_output')),
      );
    });

    test('示例模式不调用 AI', () async {
      final fake = FakeResponses([]);
      final ai = DirectAi(kb: kb, client: fake);
      final a = await ai.task('analyze', {}, demo: true);
      expect(a['problem_text'], contains('-3-(-5)'));
      expect(fake.requests, isEmpty);
    });
  });

  group('额度监控', () {
    final kps = [{'kpId': '7A-1-04', 'reason': ''}, {'kpId': '7A-2-02', 'reason': ''}];

    test('每次调用都记账：成功记 token，额度用完记时间，提示里说最晚几点恢复', () async {
      final lessons = (demo['training'] as Map)['lessons'] as List;
      final fake = FakeResponses([jsonEncode({'lessons': lessons}), 'QUOTA']);
      final ai = DirectAi(kb: kb, client: fake);
      await ai.task('training', {'problemText': '计算', 'kps': kps});
      var u = await AiUsage.load();
      expect(u.calls.single.ok, isTrue);
      expect(u.calls.single.tokens, 1200);
      expect(u.exhausted(), isFalse);

      await expectLater(
        ai.task('training', {'problemText': '计算', 'kps': kps}),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'quota').having((e) => e.message, 'message', contains('最晚'))),
      );
      u = await AiUsage.load();
      expect(u.exhausted(), isTrue);
      expect(u.recoverBy!.difference(DateTime.fromMillisecondsSinceEpoch(u.quotaAt!)), const Duration(hours: 5));
      expect(u.exhausted(now: DateTime.now().add(const Duration(hours: 6))), isFalse, reason: '5 小时后一定恢复了');
      expect(u.tokensInWindow(), 1200);
    });

    test('额度用完之后再成功一次，就不算用完了', () async {
      final lessons = (demo['training'] as Map)['lessons'] as List;
      final ai = DirectAi(kb: kb, client: FakeResponses(['QUOTA', jsonEncode({'lessons': lessons})]));
      await expectLater(ai.task('training', {'problemText': '计算', 'kps': kps}), throwsA(isA<AiException>()));
      expect((await AiUsage.load()).exhausted(), isTrue);
      await ai.task('training', {'problemText': '计算', 'kps': kps});
      expect((await AiUsage.load()).exhausted(), isFalse);
    });
  });
}
