import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_data.dart';
import 'i18n.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/local_db.dart';
import 'theme/pixel_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await i18n.load();
  await GameData.load();
  // 家庭版升级上来：把当时没传上后端的学习事件收进本机
  await (await LocalDb.open()).ingestLegacyQueue();
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/licenses/fusion-pixel-OFL.txt');
    yield LicenseEntryWithLineBreaks(['Fusion Pixel Font'], ofl);
  });
  runApp(const BennyMathApp());
}

class BennyMathApp extends StatefulWidget {
  const BennyMathApp({super.key});

  @override
  State<BennyMathApp> createState() => _BennyMathAppState();
}

/// 记录学习时长：App 在前台的时间，切到后台时记一次 session.ended（少于 20 秒不算）
class _BennyMathAppState extends State<BennyMathApp> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _since = DateTime.now();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => _since = DateTime.now(),
      onShow: () => _since ??= DateTime.now(),
      onHide: _flush,
      onPause: _flush,
    );
  }

  Future<void> _flush() async {
    final since = _since;
    _since = null;
    if (since == null) return;
    final seconds = DateTime.now().difference(since).inSeconds;
    if (seconds < 20) return;
    try {
      await LocalDb.instance.record('session.ended', {'seconds': math.min(seconds, 4 * 3600)});
    } catch (e) {
      debugPrint('记录学习时长失败：$e');
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// 换语言时整个界面重建（回到首页）
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: i18n,
        builder: (context, _) => MaterialApp(
          key: ValueKey(i18n.lang),
          title: 'Benny Math',
          debugShowCheckedModeBanner: false,
          theme: buildPixelTheme(),
          home: const _StartGate(),
        ),
      );
}

/// 第一次打开先走引导（选语言、家长同意、孩子的名字），之后直接进首页
class _StartGate extends StatefulWidget {
  const _StartGate();

  @override
  State<_StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<_StartGate> {
  bool? _onboarding;

  @override
  void initState() {
    super.initState();
    OnboardingScreen.needed().then((v) {
      if (mounted) setState(() => _onboarding = v);
    });
  }

  @override
  Widget build(BuildContext context) => switch (_onboarding) {
        null => const Scaffold(),
        true => OnboardingScreen(onDone: () => setState(() => _onboarding = false)),
        false => const HomeScreen(),
      };
}
