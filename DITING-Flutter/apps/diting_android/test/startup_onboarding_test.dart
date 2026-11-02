// First-run routing: agreement -> mode selection -> onboarding, as legacy did on startup.

import 'package:diting_android/app/app.dart';
import 'package:diting_android/app/initial_agreement.dart';
import 'package:diting_android/pages/mode/mode_onboarding_page.dart';
import 'package:diting_android/pages/mode/mode_select_page.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is only exported from `misc.dart`, not `flutter_riverpod.dart`.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  Future<void> pumpApp(
    WidgetTester tester, {
    required List<Override> overrides,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const DitingApp()),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('首次启动同意须知后进入模式选择', (tester) async {
    // Fresh prefs: the agreement is the only gate already satisfied here.
    await pumpApp(tester, overrides: const []);
    expect(find.byType(InitialAgreementDialog), findsOneWidget);

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    expect(find.byType(InitialAgreementDialog), findsNothing);
    expect(find.byType(ModeSelectPage), findsOneWidget);
  });

  testWidgets('已选模式但未完成引导时直接展示引导页', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        initialAgreementProvider.overrideWith(InitialAgreementAccepted.new),
        workModeSelectedProvider.overrideWith(WorkModeSelected.new),
      ],
    );

    expect(find.byType(ModeOnboardingPage), findsOneWidget);
    expect(find.text('引导'), findsOneWidget);
  });
}
