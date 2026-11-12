import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/ai_service.dart';
import '../i18n.dart';
import '../models/jail.dart';
import 'answer_check.dart';
import 'hunt_controller.dart' show BusyState, PhotoSet;

/// 一道放弃过的题：一步一步来（GPT 拆一次步骤，每一步拍照检查一次），学会以后在监狱里提审（自己独立重做）。
/// 错题打怪页面和怪兽监狱都用它；save 负责存档（打怪存档 + 监狱存档）。
class CoachController extends ChangeNotifier {
  CoachController({required this.c, required this.ai, required this.save, this.demo = false});

  final JailCase c;
  final AiService? ai; // 没登录 ChatGPT 时为空：只能看已经拆好的步骤、输入答案提审
  final void Function(JailCase c) save;
  final bool demo;

  late final PhotoSet photos = PhotoSet(_notify); // 这一步拍的照片（只在内存里）

  BusyState? busy;
  String? error;
  Future<void> Function()? retry;

  /// 最近一次检查这一步的结果（看不清时不往下走，提示重拍）
  Map<String, dynamic>? lastCheck;

  /// 最近一次提审的结果：{ok, counted, freed, text}；拍照提审时还有 GPT 的评语
  Map<String, dynamic>? retrial;

  CancelToken? _token;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    save(c);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }

  void cancel() => _token?.cancel();

  /// 前台等 AI：可以取消；出错时记下原因和重试
  Future<Map<String, dynamic>?> _ask(String label, String task, Map<String, dynamic> params, Future<void> Function() again) async {
    final ai = this.ai;
    if (ai == null) {
      error = tr('還沒登入 ChatGPT。請在設定裡登入。', 'Not signed in to ChatGPT. Please sign in in Settings.', 'No has iniciado sesión en ChatGPT. Inicia sesión en Ajustes.');
      retry = null;
      _notify();
      return null;
    }
    final token = _token = CancelToken();
    busy = BusyState(label);
    error = null;
    _notify();
    try {
      return await Future.any([
        ai.task(task, params, demo: demo, token: token),
        token.whenCancelled.then<Map<String, dynamic>>((_) => throw AiException('cancelled', tr('已取消', 'Cancelled', 'Cancelado'))),
      ]);
    } on AiException catch (e) {
      if (e.code != 'cancelled') {
        error = e.message;
        retry = again;
      }
      return null;
    } catch (e) {
      error = tr('出了點問題：$e', 'Something went wrong: $e', 'Algo salió mal: $e');
      retry = again;
      return null;
    } finally {
      busy = null;
      _token = null;
      _notify();
    }
  }

  void dismissError() {
    error = null;
    _notify();
  }

  // ---------- 一步一步来 ----------
  /// 开始：还没拆步骤就让 GPT 拆一次（存下来，以后不再调用），然后第 1 步讲给他看
  Future<void> start() async {
    if (!c.hasSteps) {
      final data = await _ask(
        tr('小加和小減正在把這道題拆成一小步一小步…', 'Plus and Minus are breaking this problem into small steps…', 'Más y Menos están dividiendo este problema en pasos pequeños…'),
        'steps',
        {'problemText': c.problem, 'correctAnswer': c.correctAnswer, 'solutionSteps': c.solution, 'options': c.options},
        start,
      );
      if (data == null) return;
      c.coach = data;
    }
    if (c.at == 0) c.startCoach();
    _changed();
  }

  bool get canSubmit => !c.coachDone && c.hasSteps && (photos.items.isNotEmpty || demo);

  /// 拍好了这一步：GPT 只看这一步对不对。对了直接看讲解；错了说明错在哪里，再看正确的这一步；看不清就重拍
  Future<void> submitStep() async {
    if (!canSubmit) return;
    final k = c.at + 1;
    final data = await _ask(
      tr('小加和小減正在看你的第 $k 步…', 'Plus and Minus are checking your step $k…', 'Más y Menos están revisando tu paso $k…'),
      'stepcheck',
      {
        'images': [for (final b in photos.items) imageDataUrl(b)],
        'problemText': c.problem,
        'steps': [for (final s in c.steps) {'goal': s['goal'], 'result': s['result']}],
        'step': k,
      },
      submitStep,
    );
    if (data == null) return;
    lastCheck = {...data, 'step': k};
    if (data['verdict'] == '看不清') {
      _notify();
      return;
    }
    final right = data['verdict'] == '对';
    c.finishStep(right ? 'right' : 'wrong', seen: data['seen'] as String?, where: right ? null : '${data['where']}', comment: '${data['comment']}');
    photos.clear();
    retrial = null; // 上一次提审的结果已经翻篇
    _changed();
  }

  /// 这一步不会：直接讲给他听，然后做下一步
  void tellStep() {
    if (c.coachDone || !c.hasSteps) return;
    lastCheck = null;
    retrial = null;
    c.finishStep('told');
    photos.clear();
    _changed();
  }

  /// 又放弃了一次（打怪页面里再打一遍、监狱里提审没做对）：重新关进来、重新一步一步来
  void gaveUpAgain() {
    lastCheck = null;
    retrial = null;
    photos.clear();
    c.gaveUpAgain();
    _changed();
  }

  // ---------- 提审：在监狱里自己独立重做 ----------
  /// 输入答案（App 比对，最多两次）
  void submitRetrial(String text) {
    if (text.trim().isEmpty || !c.coachDone) return;
    if (c.check(text.trim())) {
      _won(text.trim());
    } else {
      c.retrialTries += 1;
      final last = c.retrialTries >= 2;
      retrial = {'ok': false, 'last': text.trim(), 'final': last};
      if (last) c.gaveUpAgain(); // 两次都没做对：刑期从头算，再一步一步来一遍
      _changed();
    }
  }

  /// 拍照提审（没法自动比对的题）：用订正的 recheck，App 再拿最终答案和标准答案比一遍
  Future<void> submitRetrialPhoto() async {
    if (!c.coachDone || (photos.items.isEmpty && !demo)) return;
    final data = await _ask(
      tr('小加和小減正在看你的解答…', 'Plus and Minus are checking your working…', 'Más y Menos están revisando tu resolución…'),
      'recheck',
      {
        'images': [for (final b in photos.items) imageDataUrl(b)],
        'problemText': c.problem,
        'correctAnswer': c.correctAnswer,
        'solutionSteps': [for (final s in c.steps) '${s['result']}'],
      },
      submitRetrialPhoto,
    );
    if (data == null) return;
    photos.clear();
    final seen = (data['final_answer_seen'] as String?)?.trim();
    var ok = data['verdict'] == '全对' || data['verdict'] == '答案对但过程有问题';
    if (ok && c.checkable && seen != null && seen.isNotEmpty) ok = checkAnswer(seen, c.accepted, c.answerType);
    if (data['verdict'] == '看不清') {
      retrial = {'ok': false, 'unclear': true, 'comment': data['unreadable_reason']};
      _notify();
    } else if (ok) {
      _won(seen ?? '', comment: '${data['comment']}');
    } else {
      retrial = {'ok': false, 'last': seen ?? '', 'final': true, 'comment': data['comment']};
      c.gaveUpAgain();
      _changed();
    }
  }

  void _won(String last, {String? comment}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final counted = c.recordWin(now);
    retrial = {'ok': true, 'last': last, 'counted': counted, 'freed': c.freed, 'comment': ?comment};
    _changed();
  }

  void clearRetrial() {
    retrial = null;
    c.retrialTries = 0;
    _changed();
  }
}
