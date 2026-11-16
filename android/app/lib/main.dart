import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:diting_android/app/app.dart';
import 'package:diting_android/app/debug_probe.dart';
import 'package:diting_android/app/storage_v2_gate.dart';
import 'package:diting_android/data/native/runtime_events.dart';
import 'package:diting_shared/data/db/datasets.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/db/storage_v2_migration.dart';
import 'package:diting_android/data/db/rule_bootstrap.dart';
import 'package:diting_android/data/db/rule_providers.dart';
import 'package:diting_shared/data/fonts/font_repository.dart';
import 'package:diting_android/data/native/app_version.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/data/native/ca_bridge.dart';
import 'package:diting_android/data/native/data_plane_status.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_android/data/native/dns_latency_bridge.dart';
import 'package:diting_android/data/native/launcher_icon_bridge.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/overlay/floating_log_main.dart';
import 'package:diting_android/state/app_version_provider.dart';
import 'package:diting_android/state/ca_inspection_providers.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/state/launcher_icon_providers.dart';
import 'package:diting_android/state/network_tools_providers.dart';
import 'package:diting_android/state/outbound_proxy_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Opt-in startup tracing: `--dart-define=DITING_STARTUP_TRACE=true` turns the
/// `startup <stage> +Nms` lines on, so ADB (`adb logcat -s flutter`) can time the pre-frame work in a release
/// build. Off by default, so the strings and the Stopwatch are tree-shaken away.
const _startupTrace = bool.fromEnvironment('DITING_STARTUP_TRACE');

final _startupWatch = Stopwatch()..start();
int _lastStageMs = 0;

void _stage(String label) {
  final now = _startupWatch.elapsedMilliseconds;
  // Always recorded: the always-on black box is how a slow or failed startup is diagnosed
  // afterwards, even in a release build where the opt-in trace below is compiled out.
  RuntimeEvents.startup(label, now - _lastStageMs);
  _lastStageMs = now;
  if (_startupTrace) debugPrint('startup $label +${now}ms');
}

/// App entry point. The V2 storage gate runs before any provider opens a database. A real upgrade
/// copies the old stores behind the gate; a fresh install or a lost marker finishes silently before
/// the first frame.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installDebugProbe();
  _installErrorHandlers();
  _capImageCache();
  RuntimeEvents.startup('begin', 0);

  // The two loads share the wait; the rules bootstrap needs both results, so it stays last.
  final storeTask = loadLegacyPrefsStore();
  final versionTask = loadAppVersion();
  final store = await storeTask;
  _stage('prefs');
  final settings = LegacySettings(store);
  // Keep the home-screen icon in sync with the saved choice. PackageManager normally persists the
  // enabled activity-alias, but an update that rewrites the manifest resets the component flags.
  unawaited(
    reconcileLauncherIcon(
      LauncherIconBridge(),
      settings.launcherIconStyleRaw,
    ),
  );
  // Single source of truth: `pubspec.yaml`. The value feeds preset seeding,
  // cleanup actions and page display.
  final version = await versionTask;
  _stage('version');

  final state = settings.storageV2State;
  final filesReady = await storageV2FilesReady();
  var ready = StorageContract.isReadyState(state) && filesReady;
  if (!ready) {
    final gateRequired = storageV2GateRequired(
      state: state,
      filesReady: filesReady,
      legacyStoresPresent: await hasLegacyStores(),
    );
    if (!gateRequired) {
      // A fresh install has nothing to copy, and a restored preferences file can lose the marker
      // while the V2 files stay intact. Both complete silently; only a real upgrade or an
      // interrupted run shows the gate.
      final result = await ensureStorageV2(
        store,
        dataPlaneRunning: await anyDataPlaneRunning(),
      );
      ready = result.ready;
    }
  }
  _stage('storage-check');
  if (!ready) {
    runApp(
      StorageV2GateApp(
        store: store,
        onReady: () => _startApp(store, version),
      ),
    );
    return;
  }
  await _startApp(store, version);
}

Future<void> _startApp(LegacyPrefsStore store, AppVersion version) async {
  final settings = LegacySettings(store);
  // Open the data set the app starts in: the persisted work mode decides the rule database, and a
  // later mode switch opens its own database on demand.
  final dataSet = DataSet.fromWorkModeValue(settings.workModeRaw);
  final rules = await bootstrapRules(
    dataSet,
    LegacySettings(store, dnsContainer: dataSet.prefsContainer),
    versionCode: version.code,
  );
  _stage('rules');
  // Imported fonts must be registered before the first frame: the theme resolves `fontFamily` when
  // it is built, and an unknown family silently falls back to the system default.
  await FontRepository(settings: settings).registerAll();
  _stage('fonts');
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
  // First frame: the milestone a user actually feels. Reported from the post-frame callback so it
  // includes layout/paint, not just the synchronous `runApp` call.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    RuntimeEvents.startup('first_frame', _startupWatch.elapsedMilliseconds);
    unawaited(_cleanupOldStorage(store));
  });
  runApp(
    UncontrolledProviderScope(container: container, child: const DitingApp()),
  );
  _stage('runApp');
}

/// After the app has started on the V2 stores, remove the old files. A running data plane delays
/// the deletion; the same pass also removes old files restored from an Android backup.
Future<void> _cleanupOldStorage(LegacyPrefsStore store) async {
  try {
    final running = await anyDataPlaneRunning();
    if (running) return;
    if (LegacySettings(store).storageV2State == StorageContract.stateVerified) {
      final result = await cleanupStorageV2(
        store,
        dataPlaneRunning: false,
      );
      if (!result.ready) return;
      RuntimeEvents.report('db', 'storage.v2.cleaned');
    }
    await sweepLegacyDatabases(dataPlaneRunning: false);
  } catch (error) {
    debugPrint('storage cleanup skipped: $error');
  }
}

/// Aggregates the two Dart error paths into the always-on black box.
///
/// `FlutterError.onError` covers widget/build/frame errors; `PlatformDispatcher.onError` covers an
/// uncaught asynchronous exception that would otherwise only reach the console. Installed after
/// [installDebugProbe] so the debug presenter still runs (the previous handler is chained).
void _installErrorHandlers() {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    RuntimeEvents.error('flutter', details.exceptionAsString());
    if (previousFlutterError != null) {
      previousFlutterError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    RuntimeEvents.error('dart', error, stack: stack);
    // false keeps the default reporting (a console line) instead of silently swallowing it.
    return false;
  };
}

/// Default `ImageCache` is 100 MB / 1000 images. This app paints a full-screen wallpaper plus a
/// tile-sized launcher icon per row, and the decoded icons alone reach ~60 MB for a large
/// inventory, so the default ceiling let a picker trip into the ceiling and squat there. 32 MB is
/// well above what one screen plus the wallpaper needs.
void _capImageCache() {
  PaintingBinding.instance.imageCache
    ..maximumSize = 120
    ..maximumSizeBytes = 32 << 20;
}

/// Entry of the floating log window's engine, started natively by `FloatingLogWindow`; the
/// pragma keeps it out of tree shaking, since nothing in Dart calls it.
@pragma('vm:entry-point')
Future<void> floatingLogMain() => runFloatingLog();
