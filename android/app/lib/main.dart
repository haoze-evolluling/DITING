import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:diting_android/app/app.dart';
import 'package:diting_android/app/debug_probe.dart';
import 'package:diting_android/data/native/runtime_events.dart';
import 'package:diting_android/data/db/datasets.dart';
import 'package:diting_android/data/db/rule_bootstrap.dart';
import 'package:diting_android/data/db/rule_providers.dart';
import 'package:diting_android/data/fonts/font_repository.dart';
import 'package:diting_android/data/native/app_version.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/data/native/automation_bridge.dart';
import 'package:diting_android/data/native/ca_bridge.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_android/data/native/dns_latency_bridge.dart';
import 'package:diting_android/data/native/launcher_icon_bridge.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/server/server_legacy_migration.dart';
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

const _startupTrace = bool.fromEnvironment('DITING_STARTUP_TRACE');

final _startupWatch = Stopwatch()..start();
int _lastStageMs = 0;

void _stage(String label) {
  final now = _startupWatch.elapsedMilliseconds;
  RuntimeEvents.startup(label, now - _lastStageMs);
  _lastStageMs = now;
  if (_startupTrace) debugPrint('startup $label +${now}ms');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installDebugProbe();
  _installErrorHandlers();
  _capImageCache();
  RuntimeEvents.startup('begin', 0);

  final storeTask = loadLegacyPrefsStore();
  final versionTask = loadAppVersion();
  final store = await storeTask;
  _stage('prefs');
  final settings = LegacySettings(store);
  unawaited(
    reconcileLauncherIcon(LauncherIconBridge(), settings.launcherIconStyleRaw),
  );
  final version = await versionTask;
  _stage('version');
  await _startApp(store, version);
}

Future<void> _startApp(LegacyPrefsStore store, AppVersion version) async {
  final settings = LegacySettings(store);
  final dataSet = DataSet.fromWorkModeValue(settings.workModeRaw);
  if (dataSet == DataSet.server) {
    await migrateLegacyServerData(store);
  }
  final rules = await bootstrapRules(
    dataSet,
    LegacySettings(store, dnsContainer: dataSet.prefsContainer),
    versionCode: version.code,
  );
  _stage('rules');
  unawaited(AutomationBridge().reschedule());
  await FontRepository(settings: settings).registerAll();
  _stage('fonts');
  final container = ProviderContainer(
    overrides: [
      legacyPrefsStoreProvider.overrideWithValue(store),
      appVersionProvider.overrideWithValue(version),
      startupRuleRepositoryProvider.overrideWithValue(rules.repository),
      installedAppsSourceProvider.overrideWithValue(
        MethodChannelInstalledAppsSource(),
      ),
      outboundProxyStoreProvider.overrideWithValue(
        MethodChannelOutboundProxyStore(),
      ),
      caCertificateServiceProvider.overrideWithValue(
        MethodChannelCaCertificateService(),
      ),
      diagnosticsRunnerProvider.overrideWithValue(
        GuardedDiagnosticsRunner(MethodChannelDiagnosticsRunner()),
      ),
      dnsLatencyRunnerProvider.overrideWithValue(
        MethodChannelDnsLatencyRunner(),
      ),
    ],
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    RuntimeEvents.startup('first_frame', _startupWatch.elapsedMilliseconds);
  });
  runApp(
    UncontrolledProviderScope(container: container, child: const DitingApp()),
  );
  _stage('runApp');
}

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
    return false;
  };
}

void _capImageCache() {
  PaintingBinding.instance.imageCache
    ..maximumSize = 120
    ..maximumSizeBytes = 32 << 20;
}

@pragma('vm:entry-point')
Future<void> floatingLogMain() => runFloatingLog();
