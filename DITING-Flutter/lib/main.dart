import 'dart:async';

import 'package:diting/app/app.dart';
import 'package:diting/app/debug_probe.dart';
import 'package:diting/app/upgrade_resets.dart';
import 'package:diting/data/db/datasets.dart';
import 'package:diting/data/db/rule_bootstrap.dart';
import 'package:diting/data/db/rule_providers.dart';
import 'package:diting/data/db/rule_repository.dart';
import 'package:diting/data/fonts/font_repository.dart';
import 'package:diting/data/native/app_version.dart';
import 'package:diting/data/native/apps_bridge.dart';
import 'package:diting/data/native/ca_bridge.dart';
import 'package:diting/data/native/diagnostics_bridge.dart';
import 'package:diting/data/native/dns_latency_bridge.dart';
import 'package:diting/data/native/outbound_proxy_bridge.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/overlay/floating_log_main.dart';
import 'package:diting/state/app_version_provider.dart';
import 'package:diting/state/ca_inspection_providers.dart';
import 'package:diting/state/diagnostics_providers.dart';
import 'package:diting/state/installed_apps_providers.dart';
import 'package:diting/state/network_tools_providers.dart';
import 'package:diting/state/outbound_proxy_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Opt-in startup tracing: `--dart-define=DITING_STARTUP_TRACE=true` turns the
/// `startup <stage> +Nms` lines on, so ADB (`adb logcat -s flutter`) can time the pre-frame work in a release
/// build. Off by default, so the strings and the Stopwatch are tree-shaken away.
const _startupTrace = bool.fromEnvironment('DITING_STARTUP_TRACE');

/// App entry point, the only `runApp`. Legacy settings and rules load before the first
/// frame so providers see stored values instead of flashing defaults. Native channels are
/// injected here as a group: defaults are stubs, so a missing override degrades a feature.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installDebugProbe();
  final watch = Stopwatch()..start();
  var last = 0;
  void stage(String label) {
    if (!_startupTrace) return;
    debugPrint('startup $label +${watch.elapsedMilliseconds - last}ms');
    last = watch.elapsedMilliseconds;
  }

  // The two loads share the wait; the rules bootstrap needs both results, so it stays last.
  final storeTask = loadLegacyPrefsStore();
  final versionTask = loadAppVersion();
  final store = await storeTask;
  stage('prefs');
  final settings = LegacySettings(store);
  // Existing installs already accepted the agreement and chose a mode before the guide existed;
  // backfill the new flag instead of replaying onboarding after an upgrade. This mirrors legacy
  // `MainWorkModeCoordinator.checkStartupOnboarding`.
  if (settings.initialAgreementAccepted &&
      settings.workModeSelected &&
      !settings.modeOnboardingCompleted) {
    settings.setModeOnboardingCompleted(true);
  }
  // One-time resets from `upgradeResets`; before any provider reads the store, so a reset key
  // is never read with its old value.
  runUpgradeResets(store, upgradeResets);
  // Single source of truth: `pubspec.yaml`. The value feeds preset seeding,
  // cleanup actions and page display.
  final version = await versionTask;
  stage('version');
  // Open the data set the app starts in: the persisted work mode decides the rule database, and a
  // later mode switch opens its own database on demand.
  final dataSet = DataSet.fromWorkModeValue(settings.workModeRaw);
  final rules = await bootstrapRules(
    dataSet,
    LegacySettings(store, dnsContainer: dataSet.prefsContainer),
    versionCode: version.code,
  );
  stage('rules');
  // Imported fonts must be registered before the first frame: the theme resolves `fontFamily` when
  // it is built, and an unknown family silently falls back to the system default.
  await FontRepository(settings: settings).registerAll();
  stage('fonts');
  final container = ProviderContainer(
    overrides: [
      legacyPrefsStoreProvider.overrideWithValue(store),
      appVersionProvider.overrideWithValue(version),
      // The startup handle; `ruleRepositoryProvider` picks it up for its data set and opens any
      // other data set lazily when the work mode changes.
      startupRuleRepositoryProvider.overrideWithValue(rules.repository),
      // Real app list via PackageManager (QUERY_ALL_PACKAGES), shared by the four picker pages.
      installedAppsSourceProvider.overrideWithValue(
        MethodChannelInstalledAppsSource(),
      ),
      // Credentials are wrapped by AndroidKeyStore, so Dart only sees the whole config blob.
      outboundProxyStoreProvider.overrideWithValue(
        MethodChannelOutboundProxyStore(),
      ),
      caCertificateServiceProvider.overrideWithValue(
        MethodChannelCaCertificateService(),
      ),
      // Turns plugin exceptions into readable failures for the diagnostics
      // panel instead of red screens.
      diagnosticsRunnerProvider.overrideWithValue(
        GuardedDiagnosticsRunner(MethodChannelDiagnosticsRunner()),
      ),
      // Deliberately unguarded: failures are reported per item via `success=false` so the page
      // can tell "unsupported device" from "probe ran and failed".
      dnsLatencyRunnerProvider.overrideWithValue(
        MethodChannelDnsLatencyRunner(),
      ),
    ],
  );
  runApp(
    UncontrolledProviderScope(container: container, child: const DitingApp()),
  );
  // The full-table rule load used to run before `runApp` and kept the first frame waiting on the
  // biggest tables; it now lands page by page once the UI is up.
  unawaited(_loadInitialRules(container, rules.repository, watch));
}

/// Entry of the floating log window's engine, started natively by `FloatingLogWindow`; the
/// pragma keeps it out of tree shaking, since nothing in Dart calls it.
@pragma('vm:entry-point')
Future<void> floatingLogMain() => runFloatingLog();

Future<void> _loadInitialRules(
  ProviderContainer container,
  RuleRepository? repository,
  Stopwatch watch,
) async {
  final notifier = container.read(initialRulesProvider.notifier);
  await loadInitialRulesPaged(
    repository,
    (kind, page) => notifier.append(kind, page),
  );
  if (_startupTrace) {
    debugPrint('startup rules-loaded +${watch.elapsedMilliseconds}ms');
  }
}
