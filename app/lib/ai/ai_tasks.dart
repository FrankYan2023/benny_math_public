import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../game/game_data.dart';
import '../i18n.dart';
import '../models/knowledge.dart';
import 'ai_service.dart';

/// 每类 AI 任务 = 提示词（shared/ai_prompts.json）+ 规定的 JSON 输出格式 + 内容校验。
/// 每道错题只调用两类任务：analyze（看照片诊断）和 training（一次生成全部修炼内容）。
/// 另外：拍照订正 recheck；放弃一道题时 steps 拆步骤（每道题一次），每一步拍照 stepcheck（家长同意加的）。
class PreparedTask {
  PreparedTask({required this.instructions, required this.input, required this.schema, required this.validate});
  final String instructions;
  final List<Map<String, dynamic>> input;
  final Map<String, dynamic> schema;
  final List<String> Function(Map<String, dynamic> d) validate;
}

const errorTypes = ['计算失误', '概念不清', '方法不会', '审题错误', '前置缺失', '未作答', '无错误'];
const _status = ['完全不会', '做了但不确定对不对', '做错了'];
const _levels = ['基础', '变式', '提高', '挑战'];
const _answerTypes = ['数值', '表达式', '方程的解', '选择'];
// 原题的答案类型多一个"其他"（证明、作图、多问等 App 没法自动比对的题）
const _problemAnswerTypes = [..._answerTypes, '其他'];
const _tierNames = {'b': '小学衔接', 'c': '初一必备', 'e': '拓展'};
const maxKps = 4;
const maxKnown = 80; // 最多带多少道做过的题让 GPT 比对

// ---------- JSON Schema 小工具（strict 模式：所有字段必填、不允许多余字段） ----------
const _str = {'type': 'string'};
const _num = {'type': 'number'};
const _int = {'type': 'integer'};
const _bool = {'type': 'boolean'};
Map<String, dynamic> _nullable(String t) => {'type': [t, 'null']};
Map<String, dynamic> _arr(Map<String, dynamic> items) => {'type': 'array', 'items': items};
Map<String, dynamic> _obj(Map<String, dynamic> props) =>
    {'type': 'object', 'additionalProperties': false, 'required': props.keys.toList(), 'properties': props};
Map<String, dynamic> _oneOf(List<String> values) => {'type': 'string', 'enum': values};

Map<String, dynamic> _text(String t) => {'type': 'input_text', 'text': t};
Map<String, dynamic> _image(String url) => {'type': 'input_image', 'image_url': url, 'detail': 'high'};

bool _isImage(Object? s) => s is String && RegExp(r'^data:image/(jpeg|png|webp|heic);base64,').hasMatch(s) && s.length < 12000000;
AiException _bad(String message) => AiException('bad_input', message);
String _cut(Object? s, int n) {
  final t = '${s ?? ''}';
  return t.length > n ? t.substring(0, n) : t;
}

/// 照片：按顺序拍的一张或几张（题目和解答写在同一张纸上，一张写不下就拍好几张）
List<Map<String, dynamic>> _photos(Object? list, String label, String missing) {
  if (list is! List || list.isEmpty) throw _bad(missing);
  if (list.length > maxPhotos) throw _bad(tr('照片最多 $maxPhotos 張。', 'At most $maxPhotos photos.', 'Como máximo $maxPhotos fotos.'));
  if (!list.every(_isImage)) throw _bad(tr('有照片格式不對，請重拍。', 'A photo has the wrong format. Please retake it.', 'Una foto tiene un formato incorrecto. Vuelve a hacerla.'));
  if (list.length == 1) return [_text('$label：'), _image(list.first as String)];
  return [
    _text('$label（共 ${list.length} 张，按顺序，后面的接着前面的）：'),
    for (final (i, url) in list.indexed) ...[_text('第 ${i + 1} 张：'), _image(url as String)],
  ];
}

/// 答案的检查：选择题只能写字母；其他类型要有至少一种写法
List<String> _answerIssues(String n, Map q) {
  if (q['answer_type'] == '其他') return [];
  final accepted = [for (final a in q['accepted_answers'] as List) '$a'];
  return [
    if (accepted.isEmpty) '$n没有 accepted_answers',
    if (q['answer_type'] == '选择' && !accepted.every((a) => RegExp(r'^[A-D]$').hasMatch(a.trim()))) '$n是选择题，accepted_answers 只能写 A–D 的字母',
  ];
}

// 讲解卡里的动画图示：GPT 只给数据，画图和动画由 App 完成
final _visuals = [
  _obj({
    'kind': _oneOf(['number_line']), 'title': _str, 'caption': _str, 'min': _num, 'max': _num, 'step': _num,
    'points': _arr(_obj({'value': _num, 'label': _str, 'highlight': _bool})),
    'jumps': _arr(_obj({'from': _num, 'to': _num, 'label': _str})),
    'spans': _arr(_obj({'from': _num, 'to': _num, 'label': _str})),
  }),
  _obj({'kind': _oneOf(['expr_steps']), 'title': _str, 'caption': _str, 'steps': _arr(_obj({'latex': _str, 'note': _str}))}),
  _obj({'kind': _oneOf(['balance']), 'title': _str, 'caption': _str, 'steps': _arr(_obj({'left': _str, 'right': _str, 'op': _str}))}),
  _obj({
    'kind': _oneOf(['bar_model']), 'title': _str, 'caption': _str,
    'bars': _arr(_obj({'label': _str, 'total_label': _str, 'segments': _arr(_obj({'value': _num, 'label': _str}))})),
  }),
];

/// 图示的问题；没问题返回空字符串
String visualProblem(Object? v) {
  if (v == null) return '';
  if (v is! Map) return '图示格式不对';
  List<Map> list(String k) => (v[k] as List? ?? []).whereType<Map>().toList();
  double? n(Object? x) => x is num && x.isFinite ? x.toDouble() : null;
  switch (v['kind']) {
    case 'number_line':
      final min = n(v['min']), max = n(v['max']), step = n(v['step']);
      if (min == null || max == null || step == null || max <= min) return '数轴范围不对';
      if (max - min > 60 || step <= 0 || (max - min) / step > 40) return '数轴跨度或刻度不合适';
      final points = list('points'), jumps = list('jumps'), spans = list('spans');
      if (points.length > 8 || jumps.length > 6 || spans.length > 4) return '数轴上的元素太多';
      final vals = [for (final p in points) p['value'], for (final j in jumps) ...[j['from'], j['to']], for (final s in spans) ...[s['from'], s['to']]];
      if (!vals.every((x) => n(x) != null && n(x)! >= min && n(x)! <= max)) return '有数值超出数轴范围';
      if (points.isEmpty && jumps.isEmpty && spans.isEmpty) return '数轴上什么都没标';
      return '';
    case 'expr_steps':
      final steps = list('steps');
      return steps.length >= 2 && steps.length <= 8 && steps.every((s) => '${s['latex']}'.trim().isNotEmpty) ? '' : '算式步骤数量不对';
    case 'balance':
      final steps = list('steps');
      return steps.isNotEmpty && steps.length <= 6 && steps.every((s) => '${s['left']}'.trim().isNotEmpty && '${s['right']}'.trim().isNotEmpty)
          ? ''
          : '天平步骤不对';
    case 'bar_model':
      final bars = list('bars');
      return bars.isNotEmpty &&
              bars.length <= 4 &&
              bars.every((b) {
                final segs = (b['segments'] as List? ?? []).whereType<Map>().toList();
                return segs.isNotEmpty && segs.length <= 6 && segs.every((s) => (n(s['value']) ?? 0) > 0);
              })
          ? ''
          : '线段图数据不对';
    default:
      return '未知的图示类型';
  }
}


const _verdicts = ['全对', '答案对但过程有问题', '答案错', '看不清'];
const stepVerdicts = ['对', '错', '看不清'];
const maxSteps = 8;

class AiTasks {
  AiTasks(this.kb, this.game, Map<String, dynamic> rawPrompts)
      : _lang = {'zh': '${rawPrompts['LANG_zh']}', 'en': '${rawPrompts['LANG_en']}', 'es': '${rawPrompts['LANG_es']}'},
        _prompts = {
          for (final k in ['analyze', 'training', 'recheck', 'steps', 'stepcheck'])
            k: '${rawPrompts[k]}'.replaceAll('{{STUDENT}}', '${rawPrompts['STUDENT']}').replaceAll('{{STYLE}}', '${rawPrompts['STYLE']}'),
        };

  static Future<AiTasks> load(Knowledge kb) async =>
      AiTasks(kb, await GameData.load(), jsonDecode(await rootBundle.loadString('assets/ai_prompts.json')) as Map<String, dynamic>);

  final Knowledge kb;
  final GameData game; // 怪兽的形容词、宝藏的种类和材质、能力：GPT 只能从这里挑
  final Map<String, String> _prompts;
  final Map<String, String> _lang; // 给学生看的文字用哪种语言

  String _kpName(String id) => '$id ${kb.byId[id]?.name ?? ''}';
  late final String _kbText = kb.kps
      .map((k) => '${k.id} | ${k.name} | ${_tierNames[k.tier]}${k.pre.isNotEmpty ? ' | 前置: ${k.pre.join(',')}' : ''}')
      .join('\n');
  late final List<String> _allIds = [for (final k in kb.kps) k.id];

  /// p['lang']：'en' / 'es' / 'zh'（繁体，App 的界面语言），决定 GPT 写给学生的文字用哪种语言；p['student']：孩子的名字
  PreparedTask prepare(String name, Map<String, dynamic> p) {
    final t = switch (name) {
      'analyze' => _analyze(p),
      'training' => _training(p),
      'recheck' => _recheck(p),
      'steps' => _steps(p),
      'stepcheck' => _stepcheck(p),
      _ => throw AiException('bad_task', '没有这个任务：$name'),
    };
    return PreparedTask(
      instructions: t.instructions
          .replaceAll('{{LANG}}', _lang[p['lang']] ?? _lang['en']!)
          .replaceAll('{{NAME}}', '${p['student'] ?? ''}'.trim().isEmpty ? 'Benny' : '${p['student']}'.trim()),
      input: t.input,
      schema: t.schema,
      validate: t.validate,
    );
  }

  // ---------- 1. 分析一道题 ----------
  PreparedTask _analyze(Map<String, dynamic> p) {
    final pics = _photos(p['images'], '题目和学生解答的照片', tr('請先拍下題目和解答。', 'Please take a photo of the problem and your working first.', 'Primero haz una foto del problema y de tu resolución.'));
    if (!_status.contains(p['status'])) throw _bad(tr('請選擇這道題的情況。', 'Please pick how this problem went.', 'Elige cómo te fue con este problema.'));
    final note = _cut(p['note'], 300);
    // 学生以前做过的题目：让 GPT 先比对，是同一道就只回编号，App 直接打开以前的存档
    final known = [
      for (final k in (p['knownProblems'] as List? ?? []).whereType<Map>())
        if (RegExp(r'^P\d{1,3}$').hasMatch('${k['id']}') && '${k['text'] ?? ''}'.trim().isNotEmpty) k,
    ].take(maxKnown).toList();
    final knownIds = [for (final k in known) '${k['id']}'];
    return PreparedTask(
      instructions: _prompts['analyze']!,
      input: [
        {
          'role': 'user',
          'content': [
            _text('学生自述：${p['status']}${note.isNotEmpty ? '\n补充说明：$note' : ''}\n\n知识点清单（编号 | 名称 | 层级 | 前置）：\n$_kbText'),
            if (known.isNotEmpty) _text('学生以前做过的题目（编号 | 题目）：\n${[for (final k in known) '${k['id']} | ${_cut(k['text'], 300)}'].join('\n')}'),
            ...pics,
          ],
        },
      ],
      schema: _obj({
        'readable': _bool,
        'unreadable_reason': _nullable('string'),
        'problem_text': _str,
        'duplicate_of': knownIds.isEmpty
            ? {'type': 'null'}
            : {
                'anyOf': [_oneOf(knownIds), {'type': 'null'}],
              },
        'has_student_work': _bool,
        'student_answer': _nullable('string'),
        'is_correct': _nullable('boolean'),
        'correct_answer': _str,
        'answer_type': _oneOf(_problemAnswerTypes),
        'accepted_answers': _arr(_str),
        'solution_steps': _arr(_str),
        'error': _obj({'step': _nullable('integer'), 'type': _oneOf(errorTypes), 'description': _str}),
        'knowledge_points': _arr(_obj({
          'kp_id': _oneOf(_allIds), 'role': _oneOf(['主', '辅']), 'judgement': _oneOf(['会', '不会', '不确定']), 'evidence': _str,
        })),
        'missing_kps': _arr(_obj({'kp_id': _oneOf(_allIds), 'reason': _str, 'minutes': _int})),
        'plan_summary': _str,
        'estimated_minutes': _int,
        'monster': _obj({
          'personality': _oneOf(game.personalities), 'look': _oneOf(game.looks), 'color': _oneOf(game.colors), 'intro': _str,
        }),
      }),
      validate: (d) {
        final issues = <String>[];
        if (d['readable'] != true) {
          if ('${d['unreadable_reason'] ?? ''}'.isEmpty) issues.add('readable=false 时必须在 unreadable_reason 里说明怎么重拍');
          return issues;
        }
        // 认出是做过的题：其余字段不用填
        if (d['duplicate_of'] != null) return knownIds.contains(d['duplicate_of']) ? [] : ['duplicate_of 只能是清单里的编号：${knownIds.join('、')}'];
        if ('${d['problem_text']}'.trim().isEmpty) issues.add('problem_text 不能为空');
        if ('${d['correct_answer']}'.trim().isEmpty) issues.add('correct_answer 不能为空');
        if ((d['solution_steps'] as List).isEmpty) issues.add('solution_steps 不能为空');
        if ((d['knowledge_points'] as List).isEmpty) issues.add('knowledge_points 至少要有 1 个');
        issues.addAll(_answerIssues('原题', d));
        final ids = [for (final m in d['missing_kps'] as List) (m as Map)['kp_id']];
        if (ids.length > maxKps) issues.add('missing_kps 最多 $maxKps 个');
        if (ids.toSet().length != ids.length) issues.add('missing_kps 里有重复的知识点');
        if (d['is_correct'] == false && ids.isEmpty && !['计算失误', '审题错误'].contains((d['error'] as Map)['type'])) {
          issues.add('学生做错了，而且不是计算失误或审题错误，missing_kps 不能为空');
        }
        if (d['has_student_work'] == false && d['is_correct'] != null) issues.add('没有学生解答时 is_correct 必须是 null');
        return issues;
      },
    );
  }

  // ---------- 2. 一次生成全部修炼内容（每个要补的知识点：讲解卡 + 例题 + 4 道练习） ----------
  PreparedTask _training(Map<String, dynamic> p) {
    final kps = [
      for (final k in (p['kps'] as List? ?? []).whereType<Map>())
        if (kb.byId.containsKey(k['kpId'])) k,
    ].take(maxKps).toList();
    if (kps.isEmpty) throw _bad(tr('沒有要學的知識點。', 'There are no topics to learn.', 'No hay temas que aprender.'));
    final ids = [for (final k in kps) '${k['kpId']}'];
    // 学生说原题"完全不会"：例题和练习都围绕原题出
    final stuck = p['status'] == '完全不会' && _cut(p['problemText'], 1500).trim().isNotEmpty;
    final listing = [
      for (final (i, k) in kps.indexed)
        () {
          final kp = kb.byId[k['kpId']]!;
          final pre = kp.pre.isEmpty ? '无' : kp.pre.map(_kpName).join('、');
          return '${i + 1}. ${_kpName(kp.id)}（${_tierNames[kp.tier]}）\n   前置知识：$pre\n   为什么要学：${_cut(k['reason'], 300)}';
        }(),
    ].join('\n');
    return PreparedTask(
      instructions: _prompts['training']!,
      input: [
        {
          'role': 'user',
          'content': [
            _text([
              if (_cut(p['problemText'], 1500).trim().isNotEmpty) ...[
                '原题：${_cut(p['problemText'], 1500)}',
                '学生在原题里的问题：${_cut(p['errorDescription'] ?? '未知', 500)}',
              ] else
                '原题：无（学生是从冒险地图直接来修炼这个知识点的，没有对应的错题）',
              if (stuck) '学生自述：原题完全不会做。',
              '要学的知识点（按这个顺序，共 ${kps.length} 个）：\n$listing',
            ].join('\n\n')),
          ],
        },
      ],
      schema: _obj({
        'lessons': _arr(_obj({
          'kp_id': _oneOf(ids),
          'card': _obj({
            'one_liner': _str, 'explanation': _str, 'mnemonic': _nullable('string'), 'pitfall': _str, 'link_to_problem': _str,
            'visual': {
              'anyOf': [..._visuals, {'type': 'null'}],
            },
          }),
          'example': _obj({'problem': _str, 'steps': _arr(_obj({'do': _str, 'why': _str})), 'answer': _str}),
          'practice': _arr(_obj({
            'level': _oneOf(_levels),
            'problem': _str,
            'answer_type': _oneOf(_answerTypes),
            'options': _arr(_str),
            'accepted_answers': _arr(_str),
            'hint1': _str,
            'hint2': _str,
            'solution_steps': _arr(_str),
          })),
          'treasure': _obj({
            'name': _str,
            'kind': _oneOf(game.kinds),
            'material': _oneOf(game.materials),
            'stats': _arr(_oneOf([for (final s in game.stats) s.name])),
            'story': _str,
          }),
        })),
      }),
      validate: (d) {
        final issues = <String>[];
        final lessons = (d['lessons'] as List).cast<Map>();
        final got = [for (final l in lessons) '${l['kp_id']}'];
        if (got.join(',') != ids.join(',')) {
          issues.add('lessons 必须按顺序正好是这些知识点：${ids.join('、')}，现在是 ${got.isEmpty ? '空' : got.join('、')}');
        }
        for (final l in lessons) {
          final at = '${l['kp_id']} 的';
          final card = l['card'] as Map;
          // 图示只是辅助：格式不对就去掉，不为它让 GPT 重写整份讲解
          if (visualProblem(card['visual']).isNotEmpty) card['visual'] = null;
          final practice = (l['practice'] as List).cast<Map>();
          if (practice.length != 4) {
            issues.add('${at}practice 必须正好 4 道题，现在是 ${practice.length} 道');
          } else if ([for (var i = 0; i < 4; i++) practice[i]['level'] != _levels[i]].any((x) => x)) {
            issues.add('${at}practice 的 level 必须依次是 ${_levels.join('、')}');
          }
          if ('${card['explanation']}'.length > 260) issues.add('${at}card.explanation 太长了，要在 150 字以内');
          if (((l['example'] as Map)['steps'] as List).isEmpty) issues.add('${at}example.steps 不能为空');
          for (final (i, q) in practice.indexed) {
            final n = '$at第 ${i + 1} 题';
            if ('${q['problem']}'.trim().isEmpty) issues.add('$n没有题干');
            if ((q['solution_steps'] as List).isEmpty) issues.add('$n没有 solution_steps');
            issues.addAll(_answerIssues(n, q));
            final options = q['options'] as List;
            if (q['answer_type'] == '选择') {
              if (options.length != 4) issues.add('$n是选择题，options 必须正好 4 个');
            } else if (options.isNotEmpty) {
              issues.add('$n不是选择题，options 必须是空数组');
            }
          }
          final t = l['treasure'] as Map;
          final tn = '${t['name']}'.trim().length;
          final stats = [for (final s in t['stats'] as List) '$s'];
          if (tn < 2 || tn > 12) issues.add('${at}treasure.name 要 2–12 个字');
          if (stats.isEmpty || stats.length > 2 || stats.toSet().length != stats.length) issues.add('${at}treasure.stats 要选 1–2 个不重复的能力');
          if ('${t['story']}'.length > 80) issues.add('${at}treasure.story 太长了，要在 40 字左右');
        }
        return issues;
      },
    );
  }

  // ---------- 3. 订正：看学生重新做的原题（拍照），判断对不对 ----------
  PreparedTask _recheck(Map<String, dynamic> p) {
    final pics = _photos(p['images'], '学生订正的解答', tr('請先拍下訂正好的解答。', 'Please take a photo of your corrected working first.', 'Primero haz una foto de tu corrección.'));
    if (_cut(p['problemText'], 1500).trim().isEmpty) throw _bad(tr('缺少原題。', 'The original problem is missing.', 'Falta el problema original.'));
    return PreparedTask(
      instructions: _prompts['recheck']!,
      input: [
        {
          'role': 'user',
          'content': [
            _text([
              '原题：${_cut(p['problemText'], 1500)}',
              '正确答案：${_cut(p['correctAnswer'], 300)}',
              '标准解法：\n${(p['solutionSteps'] as List? ?? []).take(12).join('\n')}',
            ].join('\n\n')),
            ...pics,
          ],
        },
      ],
      schema: _obj({
        'verdict': _oneOf(_verdicts),
        'unreadable_reason': _nullable('string'),
        'final_answer_seen': _nullable('string'),
        'first_error_step': _nullable('integer'),
        'error_type': _oneOf(errorTypes),
        'comment': _str,
      }),
      validate: (d) {
        if (d['verdict'] == '看不清') return '${d['unreadable_reason'] ?? ''}'.isEmpty ? ['verdict 为"看不清"时必须说明怎么重拍'] : [];
        final issues = <String>[];
        if (d['verdict'] == '全对' && (d['first_error_step'] != null || d['error_type'] != '无错误')) {
          issues.add('判为"全对"时 first_error_step 必须是 null，error_type 必须是"无错误"');
        }
        if (d['verdict'] == '答案错' && d['error_type'] == '无错误') issues.add('判为"答案错"时 error_type 不能是"无错误"');
        if ('${d['comment']}'.trim().isEmpty) issues.add('comment 不能为空');
        return issues;
      },
    );
  }

  // ---------- 4. 放弃一道题：把解法拆成步骤（第 1 步讲给学生看，后面每一步先让学生自己做） ----------
  PreparedTask _steps(Map<String, dynamic> p) {
    final problem = _cut(p['problemText'], 1500);
    if (problem.trim().isEmpty) throw _bad(tr('缺少題目。', 'The problem is missing.', 'Falta el problema.'));
    final options = [for (final o in (p['options'] as List? ?? []).take(4)) '$o'];
    final ref = [for (final st in (p['solutionSteps'] as List? ?? []).take(12)) '$st'];
    return PreparedTask(
      instructions: _prompts['steps']!,
      input: [
        {
          'role': 'user',
          'content': [
            _text([
              '题目：$problem',
              if (options.isNotEmpty) '选项：\n${[for (final (i, o) in options.indexed) '${'ABCD'[i]}. $o'].join('\n')}',
              '正确答案：${_cut(p['correctAnswer'], 300)}',
              '参考解法：\n${ref.isEmpty ? '（无）' : ref.join('\n')}',
            ].join('\n\n')),
          ],
        },
      ],
      schema: _obj({
        'steps': _arr(_obj({'goal': _str, 'hint': _str, 'result': _str, 'explain': _str})),
        'final_answer': _str,
        'idea': _str,
      }),
      validate: (d) {
        final issues = <String>[];
        final steps = (d['steps'] as List).cast<Map>();
        if (steps.length < 2 || steps.length > maxSteps) issues.add('steps 要有 2–$maxSteps 步，现在是 ${steps.length} 步');
        String bare(Object? x) => '${x ?? ''}'.replaceAll(RegExp(r'\s|\$'), '');
        for (final (i, st) in steps.indexed) {
          final n = '第 ${i + 1} 步';
          if (['goal', 'hint', 'result', 'explain'].any((k) => '${st[k]}'.trim().isEmpty)) issues.add('$n的 goal、hint、result、explain 都不能为空');
          if ('${st['goal']}'.length > 80) issues.add('$n的 goal 太长了，要在 30 字左右');
          if ('${st['explain']}'.length > 400) issues.add('$n的 explain 太长了，要在 200 字以内');
          // 结果（或者结果里最后一个等号右边）出现在目标、提示里，就等于直接告诉他了
          final r = bare(st['result']);
          final told = [r, r.split('=').last].where((x) => x.length >= 3);
          if (told.any((x) => bare(st['goal']).contains(x) || bare(st['hint']).contains(x))) issues.add('$n的 goal 或 hint 里写出了这一步的结果，要去掉，只给方向');
        }
        if ('${d['final_answer']}'.trim().isEmpty) issues.add('final_answer 不能为空');
        if ('${d['idea']}'.length > 120) issues.add('idea 太长了，要在 50 字以内');
        return issues;
      },
    );
  }

  // ---------- 5. 一步一步做：检查学生自己做的这一步（拍照） ----------
  PreparedTask _stepcheck(Map<String, dynamic> p) {
    final pics = _photos(p['images'], '学生这一步的照片', tr('請先拍下你這一步寫的。', 'Please take a photo of this step first.', 'Primero haz una foto de este paso.'));
    final problem = _cut(p['problemText'], 1500);
    if (problem.trim().isEmpty) throw _bad(tr('缺少題目。', 'The problem is missing.', 'Falta el problema.'));
    final all = (p['steps'] as List? ?? []).whereType<Map>().take(maxSteps).toList();
    final k = p['step'];
    if (k is! int || k < 1 || k > all.length) throw _bad(tr('要檢查的步驟不對。', 'Wrong step to check.', 'Paso incorrecto para revisar.'));
    String line(Map st) => '${_cut(st['goal'], 200)} → ${_cut(st['result'], 300)}';
    final before = [for (final (i, st) in all.take(k - 1).indexed) '${i + 1}. ${line(st)}'];
    return PreparedTask(
      instructions: _prompts['stepcheck']!,
      input: [
        {
          'role': 'user',
          'content': [
            _text([
              '题目：$problem',
              '前面已经完成的步骤：\n${before.isEmpty ? '（无）' : before.join('\n')}',
              '这一步（第 $k 步）要做的：${_cut(all[k - 1]['goal'], 200)}\n参考结果：${_cut(all[k - 1]['result'], 300)}',
            ].join('\n\n')),
            ...pics,
          ],
        },
      ],
      schema: _obj({'verdict': _oneOf(stepVerdicts), 'seen': _nullable('string'), 'where': _str, 'comment': _str}),
      validate: (d) {
        if (d['verdict'] == '看不清') return '${d['where']}'.trim().isEmpty ? ['verdict 为"看不清"时 where 必须说明怎么重拍'] : [];
        return [
          if (d['verdict'] == '错' && '${d['where']}'.trim().isEmpty) 'verdict 为"错"时 where 必须具体说明错在哪里',
          if ('${d['comment']}'.trim().isEmpty) 'comment 不能为空',
        ];
      },
    );
  }

  /// 校验不过时追加给 GPT 的"请修正"消息
  static Map<String, dynamic> fixRequest(List<String> issues, String lastText) => {
        'role': 'user',
        'content': [
          _text('你上一次的输出有这些问题，请修正后重新输出完整的 JSON：\n- ${issues.join('\n- ')}\n\n上一次的输出：\n${lastText.substring(0, math.min(20000, lastText.length))}'),
        ],
      };
}
