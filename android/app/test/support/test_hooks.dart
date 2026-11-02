import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
// `Override` is only exported from `misc.dart`, not `flutter_riverpod.dart`.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Call once before mounting `DitingApp`: stops the demo rate curve (a frame per second, so
/// `pumpAndSettle` times out) and skips the agreement dialog that would block taps
void installGlobalTestHooks({bool skipInitialAgreement = true}) {
  setUp(() {
    debugDisableDashboardLiveUpdates = true;
    // The app follows the device language by default and the test platform reports en_US; pin
    // Chinese so every Chinese expectation in the suites keeps matching the shipped strings.
    final dispatcher = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(dispatcher.clearLocalesTestValue);
  });
  tearDown(() {
    debugDisableDashboardLiveUpdates = false;
  });
}

/// Every test mounting `DitingApp` should use this list, so a new global prerequisite is one edit
List<Override> appTestOverrides({
  bool skipInitialAgreement = true,
  bool skipStartupOnboarding = true,
}) => [
  if (skipInitialAgreement)
    initialAgreementProvider.overrideWith(InitialAgreementAccepted.new),
  // Otherwise the first-run redirect would send every test to mode selection.
  if (skipStartupOnboarding) ...[
    workModeSelectedProvider.overrideWith(WorkModeSelected.new),
    onboardingProvider.overrideWith(OnboardingCompleted.new),
  ],
];

/// Always reports the agreement as accepted, injected by [appTestOverrides].
class InitialAgreementAccepted extends InitialAgreementNotifier {
  @override
  bool build() => true;
}

/// Pretends the user already picked a mode, injected by [appTestOverrides].
class WorkModeSelected extends WorkModeSelectedNotifier {
  @override
  bool build() => true;
}

/// Pretends onboarding is finished, injected by [appTestOverrides].
class OnboardingCompleted extends OnboardingNotifier {
  @override
  bool build() => true;
}
