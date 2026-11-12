import 'package:flutter/material.dart';
import 'package:nes_ui/nes_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n.dart';
import '../services/settings.dart';
import '../theme/pixel_theme.dart';
import '../widgets/benny.dart';
import '../widgets/common.dart';
import '../widgets/turtles.dart';

/// 第一次打开：选语言 → 给家长看的说明和同意（照片会发给 OpenAI）→ 孩子的名字。
/// 苹果要求把个人数据发给第三方 AI 之前说清楚并取得同意；OpenAI 对未成年用户也有要求，所以由家长来设置。
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  static const _key = 'onboarding.done.v1';

  /// 还没走过这几步（家长还没同意）
  static Future<bool> needed() async => (await SharedPreferences.getInstance()).getBool(_key) != true;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _agree = false;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppSettings.load().then((s) {
      if (mounted && _name.text.isEmpty) _name.text = s.studentName;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final s = await AppSettings.load();
    s.studentName = _name.text;
    await s.save();
    final p = await SharedPreferences.getInstance();
    await p.setBool(OnboardingScreen._key, true);
    await p.setInt('consent.ai.at', DateTime.now().millisecondsSinceEpoch);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final step = switch (_step) {
      0 => _language(),
      1 => _parents(),
      _ => _child(),
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: pagePadding(context), children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Benny(height: isNarrow(context) ? 96 : 126, happy: true),
                const SizedBox(width: 6),
                Turtles(size: isNarrow(context) ? 60 : 76, mood: TurtleMood.happy),
              ]),
              const SizedBox(height: 12),
              Text('Benny Math', textAlign: TextAlign.center, style: pixelText(32, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${_step + 1} / 3', textAlign: TextAlign.center, style: pixelText(14, color: Px.shadow)),
              const SizedBox(height: 16),
              step,
            ]),
          ),
        ),
      ),
    );
  }

  Widget _language() => Panel(
        title: 'Language · Idioma · 語言',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final l in Lang.values) ...[
            PxButton(l.label, big: true, type: i18n.lang == l ? NesButtonType.primary : NesButtonType.normal, onPressed: () => i18n.set(l)),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: PxButton(tr('下一步', 'Next', 'Siguiente'), onPressed: () => setState(() => _step = 1))),
        ]),
      );

  Widget _parents() {
    Widget point(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: pixelText(16, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body, style: pixelText(14, color: Px.shadow)),
          ]),
        );
    return Panel(
      title: tr('給家長看', 'For parents', 'Para la familia'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        point(
          tr('它是做什麼的', 'What it does', 'Qué hace'),
          tr('孩子拍下做錯的數學題，AI 找出漏學的知識點，在小遊戲裡講解、練習，最後重做原題。放棄的題不直接給答案，一步一步帶著做。',
              "Your child photographs a math problem they got wrong. The AI finds the topics they are missing, then teaches and practises them in a small game before they redo the problem. Problems they give up on are never just answered; they are worked through step by step.",
              'Tu hijo o hija hace una foto de un problema de mates que le salió mal. La IA encuentra los temas que le faltan, los explica y los practica en un pequeño juego, y luego vuelve a hacer el problema. Si se rinde, no se le da la respuesta sin más: se trabaja paso a paso.'),
        ),
        point(
          tr('AI 和照片', 'AI and photos', 'IA y fotos'),
          tr('分析題目時，作業照片和題目文字會通過你自己的 ChatGPT 帳號發給 OpenAI。請提醒孩子不要拍到名字、臉或其他個人資料。AI 也可能出錯，家長可以在家長報表裡查看。',
              'To analyze a problem, the homework photo and the problem text are sent to OpenAI through your own ChatGPT account. Please remind your child not to photograph names, faces or other personal details. The AI can make mistakes; you can review everything in the parent report.',
              'Para analizar un problema, la foto de los deberes y el enunciado se envían a OpenAI a través de tu propia cuenta de ChatGPT. Recuerda a tu hijo o hija que no haga fotos de nombres, caras ni otros datos personales. La IA puede equivocarse; puedes revisarlo todo en el informe para la familia.'),
        ),
        point(
          tr('資料留在這台裝置上', 'Data stays on this device', 'Los datos se quedan en este dispositivo'),
          tr('Benny Math 沒有自己的伺服器，不收集任何資料，也沒有廣告。學習記錄只存在這台裝置上，換裝置時可以在設定裡匯出備份。',
              'Benny Math has no server of its own, collects no data and shows no ads. Progress is stored only on this device; you can export a backup in Settings when you switch devices.',
              'Benny Math no tiene servidor propio, no recoge datos y no tiene anuncios. El progreso se guarda solo en este dispositivo; puedes exportar una copia en Ajustes si cambias de dispositivo.'),
        ),
        point(
          tr('由家長來設定', 'Set up by a parent', 'Lo configura un adulto'),
          tr('適合 13 歲以上的學生。請家長用自己的 ChatGPT 帳號登入（在設定裡），AI 會用掉你 ChatGPT 方案的用量。',
              "Made for students aged 13 and up. A parent or guardian signs in with their own ChatGPT account (in Settings); the AI uses your ChatGPT plan's usage.",
              'Pensada para estudiantes a partir de 13 años. Un padre, madre o tutor inicia sesión con su propia cuenta de ChatGPT (en Ajustes); la IA usa el uso de tu plan de ChatGPT.'),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => _agree = !_agree),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NesCheckBox(value: _agree, onChange: (v) => setState(() => _agree = v)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('我是家長或監護人，我同意分析題目時把照片和題目發給 OpenAI（ChatGPT）。',
                    'I am the parent or guardian, and I agree that photos and problems are sent to OpenAI (ChatGPT) to analyze them.',
                    'Soy el padre, la madre o el tutor, y acepto que las fotos y los problemas se envíen a OpenAI (ChatGPT) para analizarlos.'),
                style: pixelText(15),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 8, children: [
          PxButton(tr('上一步', 'Back', 'Atrás'), type: NesButtonType.normal, onPressed: () => setState(() => _step = 0)),
          PxButton(tr('同意，下一步', 'Agree and continue', 'Aceptar y seguir'), onPressed: _agree ? () => setState(() => _step = 2) : null),
        ]),
      ]),
    );
  }

  Widget _child() => Panel(
        title: tr('孩子的名字', "Child's name", 'Nombre del niño o la niña'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('App 和 AI 會用這個名字稱呼孩子（可以用小名）。', 'The app and the AI will call your child by this name (a nickname is fine).', 'La app y la IA llamarán así a tu hijo o hija (vale un apodo).'),
              style: pixelText(14, color: Px.shadow)),
          const SizedBox(height: 10),
          TextField(controller: _name, autocorrect: false, style: pixelText(18), decoration: const InputDecoration(hintText: 'Benny')),
          const SizedBox(height: 16),
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 8, children: [
            PxButton(tr('上一步', 'Back', 'Atrás'), type: NesButtonType.normal, onPressed: () => setState(() => _step = 1)),
            PxButton(tr('開始冒險！', "Let's go!", '¡A jugar!'), big: true, onPressed: _finish),
          ]),
        ]),
      );
}
