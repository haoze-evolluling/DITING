import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/data/server/server_client.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';

import 'fake_server_client.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

void installGlobalTestHooks({bool skipInitialAgreement = true}) {
  setUp(() {
    debugDisableDashboardLiveUpdates = true;
    final dispatcher =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(dispatcher.clearLocalesTestValue);
  });
  tearDown(() {
    debugDisableDashboardLiveUpdates = false;
  });
}

List<Override> appTestOverrides({
  bool skipInitialAgreement = true,
  bool skipStartupOnboarding = true,
  ServerClient? serverClient,
}) => [
  if (skipInitialAgreement)
    initialAgreementProvider.overrideWith(InitialAgreementAccepted.new),
  if (skipStartupOnboarding) ...[
    workModeSelectedProvider.overrideWith(WorkModeSelected.new),
    onboardingProvider.overrideWith(OnboardingCompleted.new),
  ],
  serverClientProvider.overrideWithValue(serverClient ?? FakeServerClient()),
];

class InitialAgreementAccepted extends InitialAgreementNotifier {
  @override
  bool build() => true;
}

class WorkModeSelected extends WorkModeSelectedNotifier {
  @override
  bool build() => true;
}

class OnboardingCompleted extends OnboardingNotifier {
  @override
  bool build() => true;
}
