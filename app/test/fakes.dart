import 'dart:io';

import 'package:benny_math/ai/ai_service.dart';
import 'package:benny_math/models/hunt.dart';
import 'package:benny_math/models/jail.dart';
import 'package:benny_math/services/local_db.dart';

Map<String, dynamic> fakeLesson(String kpId) => {
      'kp_id': kpId,
      'card': {'one_liner': 'a-b=a+(-b)', 'explanation': '...', 'mnemonic': null, 'pitfall': '...', 'link_to_problem': '...', 'visual': null},
      'example': {'problem': '7-(-2)', 'steps': [{'do': '7+2', 'why': '...'}, {'do': '=9', 'why': '...'}], 'answer': '9'},
      'practice': [
        {'level': '基础', 'problem': '5-(-3)', 'answer_type': '数值', 'options': [], 'accepted_answers': ['8'], 'hint1': 'h1', 'hint2': 'h2', 'solution_steps': ['8']},
        {'level': '变式', 'problem': '-6-(-8)', 'answer_type': '数值', 'options': [], 'accepted_answers': ['2'], 'hint1': 'h1', 'hint2': 'h2', 'solution_steps': ['2']},
        {'level': '提高', 'problem': '-2.5-(-4.5)', 'answer_type': '数值', 'options': [], 'accepted_answers': ['2'], 'hint1': 'h1', 'hint2': 'h2', 'solution_steps': ['2']},
        {
          'level': '挑战', 'problem': '温差', 'answer_type': '选择', 'options': ['11', '12', '13', '14'], 'accepted_answers': ['C'],
          'hint1': 'h1', 'hint2': 'h2', 'solution_steps': ['13'],
        },
      ],
      'treasure': {'name': '变号之剑', 'kind': '剑', 'material': '黄金', 'stats': ['计算力', '专注力'], 'story': '一剑劈下，负号就变了。'},
    };

/// 假的 AI：按任务名返回固定结果，记下调用了哪些任务
class FakeAi implements AiService {
  FakeAi({this.missing = const ['7A-1-04', '7A-2-02'], this.answerType = '数值', this.duplicateOf, this.recheck, this.stepVerdicts = const []});
  final List<String> missing;
  final String answerType;
  final String? duplicateOf; // 假装 GPT 认出是做过的题
  final Map<String, dynamic>? recheck; // 拍照订正时 GPT 的判断
  final List<String> stepVerdicts; // 一步一步来：每次检查一步时 GPT 依次给的判定（用完了就判"对"）
  var _step = 0;
  final calls = <String>[];
  final received = <Map<String, dynamic>>[]; // 每次调用收到的参数

  @override
  String get label => '假 AI';

  @override
  Future<Map<String, dynamic>> task(String name, Map<String, dynamic> params, {bool demo = false, CancelToken? token}) async {
    calls.add(name);
    received.add(params);
    switch (name) {
      case 'analyze':
        if (duplicateOf != null) {
          return {'readable': true, 'unreadable_reason': null, 'problem_text': r'计算：$-3-(-5)$', 'duplicate_of': duplicateOf};
        }
        return {
          'readable': true, 'unreadable_reason': null, 'problem_text': r'计算：$-3-(-5)$', 'duplicate_of': null, 'has_student_work': true,
          'student_answer': '-8', 'is_correct': false, 'correct_answer': '2',
          'answer_type': answerType, 'accepted_answers': answerType == '其他' ? [] : ['2'],
          'solution_steps': ['-3+5', '=2'],
          'error': {'step': 1, 'type': '概念不清', 'description': '减去负数没变号'},
          'knowledge_points': [{'kp_id': '7A-2-02', 'role': '主', 'judgement': '不会', 'evidence': '...'}],
          'missing_kps': [for (final id in missing) {'kp_id': id, 'reason': '原题出错的原因', 'minutes': 8}],
          'plan_summary': '先学减法', 'estimated_minutes': 12,
          'monster': {'personality': '慌张', 'look': '长角', 'color': '火红', 'intro': '它专偷负号。'},
        };
      case 'recheck':
        return recheck ??
            {'verdict': '全对', 'unreadable_reason': null, 'final_answer_seen': '2', 'first_error_step': null, 'error_type': '无错误', 'comment': '好'};
      case 'steps':
        return {
          'steps': [
            {'goal': '把减法变成加法', 'hint': '减去一个数等于加上它的相反数', 'result': r'$-3+5$', 'explain': r'减去 $-5$ 就是加上 $5$，写成 $-3+5$。'},
            {'goal': '算出结果', 'hint': '异号相加', 'result': r'$2$', 'explain': r'$-3+5=2$。'},
            {'goal': '检查', 'hint': '代回去看看', 'result': r'$2$', 'explain': '答案是 2。'},
          ],
          'final_answer': r'$2$',
          'idea': '减负数变加正数。',
        };
      case 'stepcheck':
        final v = _step < stepVerdicts.length ? stepVerdicts[_step] : '对';
        _step += 1;
        return {'verdict': v, 'seen': v == '看不清' ? null : '-3-5', 'where': v == '对' ? '' : '减号没变', 'comment': '加油'};
      case 'training':
        return {
          'lessons': [for (final k in params['kps'] as List) fakeLesson((k as Map)['kpId'] as String)],
        };
    }
    throw UnimplementedError(name);
  }
}

/// 假的本机数据库：记下事件和存档，不写文件（没覆盖的方法写进一个临时目录）
class FakeDb extends LocalDb {
  FakeDb() : super(Directory.systemTemp.createTempSync('benny-test-'));
  final events = <(String, Map<String, dynamic>)>[];
  final saved = <String, Map<String, dynamic>>{};
  final villages = <String, Map<String, dynamic>>{};

  @override
  Future<void> record(String type, Map<String, dynamic> payload) async => events.add((type, payload));

  @override
  Future<void> saveHunt(HuntSession s) async => saved[s.pid] = s.toJson();

  @override
  Future<void> saveVillage(HuntSession s) async => villages[s.village!] = s.toJson();

  /// 怪兽监狱
  final jail = <String, Map<String, dynamic>>{};

  @override
  Future<void> saveJail(JailCase c) async => jail[c.id] = c.toJson();

  @override
  Future<JailCase?> getJail(String id) async => jail[id] == null ? null : JailCase.fromJson(jail[id]!);

  @override
  Future<List<JailCase>> listJail() async => [for (final j in jail.values) JailCase.fromJson(j)];

  /// 怪兽屋里已有的题
  final archive = <HuntSummary>[];

  @override
  Future<List<HuntSummary>> listHunts({int limit = 50}) async => archive.take(limit).toList();
}
