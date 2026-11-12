import 'package:benny_math/i18n.dart';
import 'package:benny_math/screens/onboarding_screen.dart';
import 'package:benny_math/services/settings.dart';
import 'package:benny_math/theme/pixel_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 第一次打开的引导：不同意就不能往下走；走完记下名字和同意的时间，下次不再出现
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    i18n.setForTest(Lang.en);
  });

  testWidgets('选语言 → 家长同意 → 名字', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    expect(await t.runAsync(OnboardingScreen.needed), isTrue);
    var done = false;
    await t.pumpWidget(MaterialApp(theme: buildPixelTheme(), home: OnboardingScreen(onDone: () => done = true)));
    await t.pump(const Duration(milliseconds: 300));

    Future<void> tap(String text) async {
      await t.ensureVisible(find.text(text));
      await t.pump();
      await t.tap(find.text(text));
      await t.pump(const Duration(milliseconds: 300));
    }

    await tap('Next');
    expect(find.text('For parents'), findsOneWidget);
    await tap('Agree and continue');
    expect(find.text('For parents'), findsOneWidget, reason: '没勾同意不能往下走');
    await t.ensureVisible(find.textContaining('I am the parent or guardian'));
    await t.tap(find.textContaining('I am the parent or guardian'));
    await t.pump();
    await tap('Agree and continue');
    expect(find.text("Child's name"), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Lucía');
    await tap("Let's go!");
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(done, isTrue);
    expect((await t.runAsync(AppSettings.load))!.studentName, 'Lucía');
    expect(await t.runAsync(OnboardingScreen.needed), isFalse);
    expect((await t.runAsync(SharedPreferences.getInstance))!.getInt('consent.ai.at'), isNotNull);
    await t.pumpWidget(const SizedBox());
  });
}
