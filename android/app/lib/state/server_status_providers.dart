/// Server-mode state and port, separate from the VPN power state so the two modes cannot
/// contaminate each other.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';

import 'package:diting_android/data/notifications/notification_status_text.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/server/dns_server_bridge.dart';
import 'package:diting_android/data/server/dns_server_config.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ServerPortNotifier extends Notifier<int> {
  @override
  int build() => ref.read(legacySettingsProvider).serverPort;

  void set(int port) {
    final clamped = port.clamp(1024, 65535);
    state = clamped;
    ref.read(legacySettingsProvider).setServerPort(clamped);
  }
}

final serverPortProvider = NotifierProvider<ServerPortNotifier, int>(
  ServerPortNotifier.new,
);

/// Five-state server-mode status card.
enum ServerStatus {
  stopped,
  starting,
  running,
  stopping,
  error;

  String label(AppL10n l10n) => switch (this) {
    ServerStatus.stopped => l10n.stateStopped,
    ServerStatus.starting => l10n.stateStarting,
    ServerStatus.running => l10n.stateRunning,
    ServerStatus.stopping => l10n.stateStopping,
    ServerStatus.error => l10n.serverStatusError,
  };
}

class ServerStatusNotifier extends Notifier<ServerStatus> {
  /// Deadline for a start/stop attempt: both commands answer once scheduled, so a longer wait means
  /// a wedged round trip.
  static const Duration _guardTimeout = Duration(seconds: 30);

  bool _disposed = false;
  Timer? _statsTimer;
  Timer? _uptimeTimer;
  Timer? _guardTimer;

  /// Last native failure, kept for diagnostics only.
  String? lastError;

  @override
  ServerStatus build() {
    ref.onDispose(() {
      _disposed = true;
      _statsTimer?.cancel();
      _uptimeTimer?.cancel();
      _guardTimer?.cancel();
    });
    // Leaving server mode must not leave a LAN DNS listener behind while the UI shows another mode.
    ref.listen(workModeProvider, (previous, next) {
      if (next != AppWorkMode.server &&
          (state == ServerStatus.running || state == ServerStatus.starting)) {
        unawaited(_stop());
      }
    });
    if (ref.read(legacySettingsProvider).serverServiceActive) {
      // The flag survives process death; confirm with the native side before claiming the listener
      // is up.
      scheduleMicrotask(syncStatus);
      _armGuard();
      return ServerStatus.starting;
    }
    return ServerStatus.stopped;
  }

  Future<void> syncStatus() async {
    final mode = ref.read(workModeProvider);
    try {
      final status = await ref.read(dnsServerControllerProvider).status();
      if (_disposed) return;
      ref.read(legacySettingsProvider).setServerServiceActive(status.running);
      if (status.error != null && !status.running) {
        lastError = status.error;
        state = ServerStatus.error;
      } else {
        state = status.running ? ServerStatus.running : ServerStatus.stopped;
      }
      _guardTimer?.cancel();
      ref
          .read(serviceStatsProvider.notifier)
          .applyNative(
            status.stats,
            running: status.running,
            // Outside server mode the VPN plane owns the counters, so its "not running" is
            // expected and must not clear the live uptime.
            ownsStats: mode == AppWorkMode.server,
            startedAt: status.startedAt,
          );
      if (status.running) {
        _ensureStatsPolling();
      } else {
        _cancelStatsPolling();
      }
    } catch (_) {
      if (!_disposed) {
        state = ServerStatus.stopped;
        _guardTimer?.cancel();
      }
    }
  }

  Future<void> toggle() async {
    // Ignore taps in the two transient states; each already awaits native confirmation, so a second
    // would interleave.
    if (state == ServerStatus.starting || state == ServerStatus.stopping) {
      return;
    }
    if (state == ServerStatus.running) {
      await _stop();
      return;
    }
    await _start();
  }

  Future<void> _start() async {
    if (ref.read(workModeProvider) != AppWorkMode.server) {
      _fail(currentL10n.serverModeRequired);
      return;
    }
    // Only one tunnel-like data plane at a time: stop the VPN before binding.
    await ref.read(powerProvider.notifier).stopIfActive();
    if (_disposed) return;
    // Create the server's own log store before the native writers start; otherwise a first run
    // would drop every row until a log page happened to open the file.
    try {
      await LegacyDatabase.open(LegacyDatabase.serverLogFile);
    } catch (_) {
      // A missing schema only costs log rows, not the DNS service itself.
    }
    state = ServerStatus.starting;
    lastError = null;
    _armGuard();
    final settings = ref.read(legacySettingsProvider);
    try {
      final config = buildServerDnsConfig(settings);
      // Composed here: the service has no provider catalog to build the upstream line from.
      settings.setNotificationDefaultServerText(
        defaultServerNotificationText(settings),
      );
      // Rules are no longer loaded or shipped here: the service builds the engine
      // snapshot in its own process, so the rule set never crosses the Binder limit.
      final result = await ref
          .read(dnsServerControllerProvider)
          .start(
            DnsServerStartRequest(
              port: config.port,
              dnsConfig: config.encode(),
              adBlockEnabled: config.adBlockEnabled,
            ),
          );
      if (_disposed) return;
      if (!result.started) {
        _fail(result.error ?? currentL10n.serverStartFailed);
        return;
      }
      settings.setServerServiceActive(true);
      ref.read(serviceStatsProvider.notifier).markStarted();
      state = ServerStatus.running;
      _guardTimer?.cancel();
      _ensureStatsPolling();
      Timer(const Duration(milliseconds: 700), syncStatus);
    } catch (error) {
      if (!_disposed) _fail(_messageOf(error));
    }
  }

  void _ensureStatsPolling() {
    // Counters every 3 s; uptime ticks locally every second (see PowerNotifier).
    _statsTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => syncStatus(),
    );
    _uptimeTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => ref.read(serviceStatsProvider.notifier).refreshUptime(),
    );
  }

  void _cancelStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
  }

  Future<void> _stop() async {
    _cancelStatsPolling();
    state = ServerStatus.stopping;
    _armGuard();
    try {
      await ref.read(dnsServerControllerProvider).stop();
    } catch (error) {
      lastError = _messageOf(error);
    }
    if (_disposed) return;
    ref.read(legacySettingsProvider).setServerServiceActive(false);
    ref.read(serviceStatsProvider.notifier).reset();
    state = ServerStatus.stopped;
    _guardTimer?.cancel();
  }

  /// Arms the deadline for the current transient state; on expiry it asks the native side what is
  /// actually running.
  void _armGuard() {
    _guardTimer?.cancel();
    _guardTimer = Timer(_guardTimeout, () {
      if (_disposed) return;
      if (state != ServerStatus.starting && state != ServerStatus.stopping) {
        return;
      }
      if (state == ServerStatus.stopping) {
        // The flag is already gone; show idle rather than an endless spinner.
        state = ServerStatus.stopped;
        return;
      }
      syncStatus().then((_) {
        if (_disposed || state != ServerStatus.starting) return;
        _fail(currentL10n.serverStartTimeout);
      });
    });
  }

  void _fail(String message) {
    _guardTimer?.cancel();
    lastError = message;
    ref.read(legacySettingsProvider).setServerServiceActive(false);
    state = ServerStatus.error;
  }

  static String _messageOf(Object error) => error is PlatformException
      ? (error.message ?? error.code)
      : error.toString();
}

final dnsServerControllerProvider = Provider<DnsServerController>(
  (ref) => MethodChannelDnsServerController(),
);

final serverStatusProvider =
    NotifierProvider<ServerStatusNotifier, ServerStatus>(
      ServerStatusNotifier.new,
    );
