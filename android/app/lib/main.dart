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
import 'package:diting_android/data/native/automation_bridge.dart';
import 'package:diting_android/data/native/ca_bridge.dart';
import 'package:diting_android/data/native/data_plane_status.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_android/data/native/dns_latency_bridge.dart';
import 'package:diting_android/data/native/launcher_icon_bridge.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_shared/data/prefs/ipv6_default_migration.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/scroll_activity.dart';
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
  migrateIpv6DefaultToIpv4(store);
  final settings = LegacySettings(store);
  unawaited(
    reconcileLauncherIcon(LauncherIconBridge(), settings.launcherIconStyleRaw),
  );
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
      StorageV2GateApp(store: store, onReady: () => _startApp(store, version)),
    );
    return;
  }
  await _startApp(store, version);
}

Future<void> _startApp(LegacyPrefsStore store, AppVersion version) async {
  final settings = LegacySettings(store);
  final dataSet = DataSet.fromWorkModeValue(settings.workModeRaw);
  final rules = await bootstrapRules(
    dataSet,
    LegacySettings(store, dnsContainer: dataSet.prefsContainer),
    versionCode: version.code,
  );
  _stage('rules');
  // 存储就绪后再按数据库规则重排一次定时，覆盖 Application 启动时迁移尚未完成的情况。
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
    unawaited(_scheduleStorageCleanup(store));
  });
  runApp(
    UncontrolledProviderScope(container: container, child: const DitingApp()),
  );
  _stage('runApp');
}

/// 存储清理是一次性的后台维护，没必要和首屏渲染 / 首次滑动抢夺资源，
/// 等启动稳定且用户停下滑动后再执行。
Future<void> _scheduleStorageCleanup(LegacyPrefsStore store) async {
  await Future<void>.delayed(const Duration(seconds: 4));
  final idle = Completer<void>();
  ScrollActivityGate.whenIdle(idle.complete);
  await idle.future;
  await _cleanupOldStorage(store);
}

Future<void> _cleanupOldStorage(LegacyPrefsStore store) async {
  try {
    final running = await anyDataPlaneRunning();
    if (running) return;
    if (LegacySettings(store).storageV2State == StorageContract.stateVerified) {
      final result = await cleanupStorageV2(store, dataPlaneRunning: false);
      if (!result.ready) return;
      RuntimeEvents.report('db', 'storage.v2.cleaned');
    }
    await sweepLegacyDatabases(dataPlaneRunning: false);
  } catch (error) {
    debugPrint('storage cleanup skipped: $error');
  }
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
