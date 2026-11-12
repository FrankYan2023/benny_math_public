import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_service.dart';
import '../ai/ai_usage.dart';
import '../ai/chatgpt_auth.dart';
import '../ai/direct_ai.dart';
import '../ai/responses_client.dart';
import '../i18n.dart';
import '../models/knowledge.dart';
import '../services/local_db.dart';
import '../services/settings.dart';
import '../theme/pixel_theme.dart';
import '../widgets/common.dart';
import 'parent_report_screen.dart';

/// 设置：语言、ChatGPT 账号和额度、孩子的名字、学习记录。
/// 每次打开都自动查一次 ChatGPT 额度。学习记录只存在这台设备上。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _name = TextEditingController();
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    AppSettings.load().then((s) {
      if (!mounted) return;
      setState(() {
        _settings = s;
        _name.text = s.studentName;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _openReport() async {
    final kb = await Knowledge.load();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParentReportScreen(kb: kb, name: _name.text.trim().isEmpty ? 'Benny' : _name.text.trim())));
  }

  /// 导出备份：存成一个文件，用系统的分享面板发出去（隔空投送、存到"文件"、发邮件…）
  Future<void> _export(BuildContext button) async {
    final box = button.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      final data = await LocalDb.instance.exportAll();
      final d = DateTime.now();
      final name = 'BennyMath-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json';
      final file = File('${(await getTemporaryDirectory()).path}/$name');
      await file.writeAsString(jsonEncode(data));
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], sharePositionOrigin: origin));
    } catch (e) {
      if (mounted) NesSnackbar.show(context, text: tr('匯出失敗：$e', 'Export failed: $e', 'No se pudo exportar: $e'), type: NesSnackbarType.error);
    }
  }

  /// 从备份恢复：先问一句，这台设备上的记录会被换掉
  Future<void> _import() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (picked == null || !mounted) return;
    final yes = await confirmBox(
      context,
      leading: const Icon(Icons.restore, size: 48, color: Px.amber),
      title: tr('從備份恢復？', 'Restore from backup?', '¿Restaurar desde la copia?'),
      body: tr('這臺裝置上現在的學習記錄、存檔和寶藏都會換成備份裡的，原來的會被刪掉。', 'All progress, saves and treasures on this device will be replaced by the backup. What is here now will be deleted.', 'Todo el progreso, las partidas guardadas y los tesoros de este dispositivo se sustituirán por los de la copia. Lo que hay ahora se borrará.'),
      ok: tr('恢復', 'Restore', 'Restaurar'),
      cancel: tr('取消', 'Cancel', 'Cancelar'),
    );
    if (!yes || !mounted) return;
    try {
      final data = jsonDecode(utf8.decode(await picked.readAsBytes()));
      if (data is! Map) throw LocalDbException(tr('這不是 Benny Math 的備份檔案。', "This isn't a Benny Math backup file.", 'Esto no es una copia de seguridad de Benny Math.'));
      await LocalDb.instance.importAll(data.cast<String, dynamic>());
      final s = await AppSettings.load();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _name.text = s.studentName;
      });
      NesSnackbar.show(context, text: tr('恢復好了！', 'Restored!', '¡Restaurado!'), type: NesSnackbarType.success);
    } catch (e) {
      if (mounted) NesSnackbar.show(context, text: tr('恢復失敗：$e', 'Restore failed: $e', 'No se pudo restaurar: $e'), type: NesSnackbarType.error);
    }
  }

  Future<void> _save() async {
    final s = _settings;
    if (s == null) return;
    s.studentName = _name.text;
    await s.save();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('設定', 'Settings', 'Ajustes'), style: pixelText(20)), backgroundColor: Px.paper),
      body: SafeArea(
        child: ListView(
          padding: pagePadding(context),
          children: [
            Panel(
              title: tr('語言', 'Language', 'Idioma'),
              child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final l in Lang.values)
                  PxButton(l.label, type: i18n.lang == l ? NesButtonType.primary : NesButtonType.normal, onPressed: () => i18n.set(l)),
                Text(
                  tr('介面和以後生成的講解、練習都用這種語言。', 'The app and any new lessons and practice will use this language.', 'La app y las nuevas lecciones y prácticas usarán este idioma.'),
                  style: pixelText(14, color: Px.shadow),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            const _ChatGptSection(),
            const SizedBox(height: 24),
            const _QuotaSection(),
            const SizedBox(height: 24),
            Panel(
              title: tr('孩子的名字', "Child's name", 'Nombre del niño o la niña'),
              child: TextField(controller: _name, autocorrect: false, style: pixelText(18), decoration: const InputDecoration(hintText: 'Benny')),
            ),
            const SizedBox(height: 24),
            Panel(
              title: tr('家長報表', 'Parent report', 'Informe para la familia'),
              child: Row(children: [
                Expanded(
                  child: Text(tr('看看掃過哪些題、哪些知識點還薄弱、錯因分佈和學習時長。', 'See which problems were scanned, which topics are still weak, kinds of mistakes and time spent.', 'Mira qué problemas se escanearon, qué temas siguen flojos, los tipos de errores y el tiempo dedicado.'),
                      style: pixelText(15)),
                ),
                const SizedBox(width: 12),
                PxButton(tr('開啟報表', 'Open report', 'Abrir informe'), type: NesButtonType.normal, onPressed: _openReport),
              ]),
            ),
            const SizedBox(height: 24),
            Panel(
              title: tr('學習記錄', 'Progress', 'Progreso'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  tr('所有學習記錄、存檔和寶藏都只存在這臺裝置上，不會上傳到任何伺服器。拍的照片只發給你登入的 ChatGPT 用來分析題目。',
                      'All progress, saves and treasures stay on this device and are never uploaded to any server. Photos are only sent to your signed-in ChatGPT to analyze the problem.', 'Todo el progreso, las partidas guardadas y los tesoros se quedan en este dispositivo y nunca se suben a ningún servidor. Las fotos solo se envían a tu ChatGPT para analizar el problema.'),
                  style: pixelText(15),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('換裝置、或者想在手機和 iPad 上接著用：先在這裡匯出備份，再到另一臺裝置上恢復。',
                      'Moving to another device, or switching between phone and iPad? Export a backup here, then restore it on the other device.', '¿Cambias de dispositivo, o quieres usarlo en el móvil y en el iPad? Exporta aquí una copia y luego restáurala en el otro dispositivo.'),
                  style: pixelText(14, color: Px.shadow),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 12, runSpacing: 10, children: [
                  Builder(builder: (b) => PxButton(tr('匯出備份', 'Export backup', 'Exportar copia'), type: NesButtonType.normal, onPressed: () => _export(b))),
                  PxButton(tr('從備份恢復', 'Restore from backup', 'Restaurar desde la copia'), type: NesButtonType.warning, onPressed: _import),
                ]),
              ]),
            ),
            const SizedBox(height: 24),
            Align(alignment: Alignment.centerRight, child: PxButton(tr('儲存', 'Save', 'Guardar'), big: true, onPressed: _save)),
          ],
        ),
      ),
    );
  }
}

/// ChatGPT 账号：用自己的 ChatGPT 账号登录（用订阅额度）。
class _ChatGptSection extends StatefulWidget {
  const _ChatGptSection();

  @override
  State<_ChatGptSection> createState() => _ChatGptSectionState();
}

class _ChatGptSectionState extends State<_ChatGptSection> {
  final _auth = ChatGptAuth();
  ChatGptAccount? _account;
  List<String> _models = [];
  String? _model;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final account = await _auth.account();
    var models = <String>[];
    String? model;
    String? message;
    if (account != null) {
      try {
        final ai = DirectAi(kb: await Knowledge.load(), auth: _auth);
        models = await ai.listModels();
        model = await ai.model();
      } on AiException catch (e) {
        message = tr('讀取模型失敗：${e.message}', "Couldn't load models: ${e.message}", 'No se pudieron cargar los modelos: ${e.message}');
      }
    }
    if (!mounted) return;
    setState(() {
      _account = account;
      _models = models;
      _model = model;
      _message = message;
    });
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _auth.signIn();
      await _refresh();
      if (mounted) await showChatGptPlanNotice(context);
    } on AiException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = tr('登入沒有完成：$e', 'Sign-in was not completed: $e', 'No se completó el inicio de sesión: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _account;
    return Panel(
      title: tr('ChatGPT 帳號', 'ChatGPT account', 'Cuenta de ChatGPT'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (a == null) ...[
          Text(
            tr('Benny Math 用你自己的 ChatGPT 方案來分析題目、準備修煉，不另外收費。請家長用自己的 ChatGPT 帳號登入。登入頁會在 App 裡開啟，登入後自動回來。',
                'Benny Math uses your own ChatGPT plan to analyze problems and prepare training, at no extra cost. A parent should sign in with their ChatGPT account. The sign-in page opens inside the app and comes back by itself.',
                'Benny Math usa tu propio plan de ChatGPT para analizar los problemas y preparar el entrenamiento, sin coste extra. Un padre, madre o tutor debe iniciar sesión con su cuenta de ChatGPT. La página de inicio de sesión se abre dentro de la app y vuelve sola.'),
            style: pixelText(15),
          ),
          const SizedBox(height: 12),
          PxButton(_busy ? tr('等待登入…', 'Waiting for sign-in…', 'Esperando el inicio de sesión…') : tr('使用 ChatGPT 繼續', 'Continue with ChatGPT', 'Continuar con ChatGPT'), onPressed: _busy ? null : _signIn),
        ] else ...[
          Text('${tr('已登入：', 'Signed in: ', 'Sesión iniciada: ')}${a.name ?? ''} ${a.email ?? ''}', style: pixelText(16, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          const ChatGptPlanTag(),
          const SizedBox(height: 10),
          if (_models.isNotEmpty)
            Row(children: [
              Text(
                tr('使用的模型（預設 ${ResponsesClient.preferredModel}，思考強度低，速度快）  ', 'Model (default ${ResponsesClient.preferredModel}, low reasoning, fast)  ', 'Modelo (por defecto ${ResponsesClient.preferredModel}, razonamiento bajo, rápido)  '),
                style: pixelText(15),
              ),
              DropdownButton<String>(
                value: _models.contains(_model) ? _model : null,
                items: [for (final m in _models) DropdownMenuItem(value: m, child: Text(m, style: pixelText(15)))],
                onChanged: (m) async {
                  if (m == null) return;
                  await DirectAi.setModel(m);
                  setState(() => _model = m);
                },
              ),
            ]),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 8, children: [
            PxButton(tr('斷開', 'Disconnect', 'Desconectar'), type: NesButtonType.normal, onPressed: () async {
              await _auth.signOut();
              await _refresh();
            }),
            PxButton(tr('換一個帳號', 'Use another account', 'Usar otra cuenta'), type: NesButtonType.normal, onPressed: () async {
              await _auth.forget();
              await _refresh();
            }),
          ]),
        ],
        if (_message != null) ...[const SizedBox(height: 10), Text(_message!, style: pixelText(14, color: Px.brick))],
      ]),
    );
  }
}

/// ChatGPT 额度监控：OpenAI 不告诉第三方应用还剩多少，这里显示 App 自己记的账。
/// 每次打开设置都自动查一次（发一个极小的请求，花一点点额度）。
class _QuotaSection extends StatefulWidget {
  const _QuotaSection();

  @override
  State<_QuotaSection> createState() => _QuotaSectionState();
}

class _QuotaSectionState extends State<_QuotaSection> {
  AiUsage? _u;
  bool _checking = false;
  String? _checkNote;

  String _taskName(String task) => switch (task) {
        'analyze' => tr('分析錯題', 'Analyze', 'Analizar'),
        'training' => tr('生成修煉', 'Training', 'Entrenamiento'),
        'recheck' => tr('看訂正', 'Correction', 'Corrección'),
        'steps' => tr('拆解題步驟', 'Step-by-step', 'Paso a paso'),
        'stepcheck' => tr('檢查一步', 'Check a step', 'Revisar un paso'),
        'check' => tr('檢查額度', 'Quota check', 'Comprobar cuota'),
        _ => task,
      };

  @override
  void initState() {
    super.initState();
    _reload().then((_) async {
      if (await ChatGptAuth().account() != null) _check();
    });
  }

  Future<void> _reload() async {
    final u = await AiUsage.load();
    if (mounted) setState(() => _u = u);
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() {
      _checking = true;
      _checkNote = null;
    });
    try {
      final ok = await checkQuota(DirectAi(kb: await Knowledge.load()));
      _checkNote = ok ? tr('剛檢查過：現在可以用。', 'Just checked: ready to use.', 'Comprobado ahora: lista para usar.') : tr('剛檢查過：額度還沒恢復。', 'Just checked: still used up.', 'Comprobado ahora: sigue agotada.');
    } on AiException catch (e) {
      _checkNote = tr('檢查失敗：${e.message}', 'Check failed: ${e.message}', 'La comprobación falló: ${e.message}');
    } finally {
      if (mounted) setState(() => _checking = false);
      await _reload();
    }
  }

  String _k(int tokens) => tokens >= 10000 ? '${(tokens / 1000).toStringAsFixed(0)}k' : '$tokens';

  @override
  Widget build(BuildContext context) {
    final u = _u;
    if (u == null) return const SizedBox.shrink();
    final out = u.exhausted();
    final today = u.today().toList();
    final last = u.calls.reversed.take(8).toList();
    final lastOk = u.calls.where((c) => c.ok).lastOrNull;
    return Panel(
      title: tr('ChatGPT 額度', 'ChatGPT quota', 'Cuota de ChatGPT'),
      color: out ? Px.sunLight : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          MarkIcon(out ? Mark.bad : Mark.ok, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              out
                  ? tr('用完了，最晚 ${hhmm(u.recoverBy!)} 恢復', 'Used up — back by ${hhmm(u.recoverBy!)} at the latest', 'Agotada: vuelve como muy tarde a las ${hhmm(u.recoverBy!)}')
                  : (lastOk == null
                      ? tr('還沒用過', 'Not used yet', 'Aún sin usar')
                      : tr('可以用（上次成功：${hhmm(DateTime.fromMillisecondsSinceEpoch(lastOk.at))}）', 'Ready (last success: ${hhmm(DateTime.fromMillisecondsSinceEpoch(lastOk.at))})', 'Lista (último uso correcto: ${hhmm(DateTime.fromMillisecondsSinceEpoch(lastOk.at))})')),
              style: pixelText(18, weight: FontWeight.w700, color: out ? Px.brick : Px.okText),
            ),
          ),
          PxButton(_checking ? tr('檢查中…', 'Checking…', 'Comprobando…') : tr('再查一次', 'Check now', 'Comprobar ahora'), type: NesButtonType.normal, onPressed: _checking ? null : _check),
        ]),
        if (_checkNote != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_checkNote!, style: pixelText(14, color: Px.shadow))),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 10, children: [
          _Stat(tr('今天呼叫', 'Calls today', 'Llamadas hoy'), tr('${today.length} 次', '${today.length}', '${today.length}')),
          _Stat(tr('今天用掉', 'Used today', 'Usado hoy'), '${_k(today.fold(0, (s, c) => s + c.tokens))} token'),
          _Stat(tr('最近 5 小時', 'Last 5 hours', 'Últimas 5 horas'), '${_k(u.tokensInWindow())} token'),
          _Stat(tr('最近 7 天', 'Last 7 days', 'Últimos 7 días'), tr('${u.calls.length} 次', '${u.calls.length} calls', '${u.calls.length} llamadas')),
        ]),
        if (last.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('最近的呼叫', 'Recent calls', 'Llamadas recientes'), style: pixelText(14, color: Px.shadow, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final c in last)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 120, child: Text(hhmm(DateTime.fromMillisecondsSinceEpoch(c.at)), style: pixelText(14, color: Px.shadow))),
                SizedBox(width: 100, child: Text(_taskName(c.task), style: pixelText(14))),
                MarkIcon(c.ok ? Mark.ok : Mark.bad, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.ok
                        ? '${_k(c.tokens)} token · ${(c.ms / 1000).toStringAsFixed(0)}${tr(' 秒', 's', 's')}'
                        : (c.code == 'quota' ? tr('額度用完了', 'Quota used up', 'Cuota agotada') : tr('失敗（${c.code}）', 'Failed (${c.code})', 'Falló (${c.code})')),
                    style: pixelText(14, color: c.ok ? Px.ink : Px.brick),
                  ),
                ),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          tr(
            'Plus 的額度按"過去 5 小時"滾動計算，和你自己用 ChatGPT、Codex 共用。OpenAI 不告訴 App 還剩多少，這裡是 App 自己記的賬；每次開啟設定會發一個極小的請求查一下現在能不能用。',
            'Plus quota is counted over a rolling 5-hour window and is shared with your own ChatGPT and Codex use. OpenAI does not tell apps how much is left, so this is the app\'s own log; opening Settings sends one tiny request to check whether it works right now.', 'La cuota de Plus se cuenta en una ventana móvil de 5 horas y se comparte con tu propio uso de ChatGPT y Codex. OpenAI no les dice a las apps cuánto queda, así que este es el registro propio de la app; al abrir Ajustes se envía una petición pequeñita para comprobar si funciona ahora mismo.',
          ),
          style: pixelText(13, color: Px.shadow),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => PixelBox(
        shadow: false,
        color: Px.paper,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: pixelText(17, weight: FontWeight.w700)),
          Text(label, style: pixelText(12, color: Px.shadow)),
        ]),
      );
}

/// 第一次登录后告诉家长：用的是你自己的 ChatGPT 方案（OpenAI 的界面规范）
Future<void> showChatGptPlanNotice(BuildContext context) async {
  final p = await SharedPreferences.getInstance();
  if (p.getBool('chatgpt.planNoticeShown') == true || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: PixelBox(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('你正在使用自己的 ChatGPT 方案', "You're using your ChatGPT plan", 'Estás usando tu plan de ChatGPT'), style: pixelText(20, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              tr('Benny Math 的 AI 功能會用掉你 ChatGPT 方案的用量。用量用完時要等它恢復，也可以在 ChatGPT 的設定裡查看。',
                  "Benny Math's AI features use your ChatGPT plan's usage. If you run out, wait for it to reset; you can also check it in your ChatGPT settings.",
                  'Las funciones de IA de Benny Math usan el uso de tu plan de ChatGPT. Si se agota, espera a que se renueve; también puedes consultarlo en los ajustes de ChatGPT.'),
              style: pixelText(15, color: Px.shadow),
            ),
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 8, children: [
              const ManageUsageButton(),
              PxButton(tr('知道了', 'Got it', 'Entendido'), onPressed: () => Navigator.of(ctx).pop()),
            ]),
          ]),
        ),
      ),
    ),
  );
  await p.setBool('chatgpt.planNoticeShown', true);
}
