part of 'work_mode_providers.dart';

class PowerNotifier extends Notifier<PowerState> {
  /// Deadline for `onPrepareResult`: it travels through the activity result and can be lost on
  /// recreate.
  static const Duration _consentTimeout = Duration(seconds: 90);

  /// Deadline for a consented start; `start()` returns once scheduled.
  static const Duration _launchTimeout = Duration(seconds: 30);

  bool _disposed = false;
  bool _pendingPermissionStart = false;

  /// Set at build when the tunnel was left running and auto start is on; the first status sync
  /// that finds it down restarts it instead of clearing the flag.
  bool _restoreOnLaunch = false;
  Timer? _statsTimer;
  Timer? _guardTimer;

  /// Last bridge failure, kept for diagnostics while the UI shows a generic label.
  String? lastError;

  bool get _isExpress => ref.read(workModeProvider) == AppWorkMode.express;

  VpnController get _controller => _isExpress
      ? ref.read(expressVpnControllerProvider)
      : ref.read(vpnControllerProvider);

  @override
  PowerState build() {
    ref.onDispose(() {
      _disposed = true;
      _statsTimer?.cancel();
      _guardTimer?.cancel();
    });
    ref.read(vpnControllerProvider).onPrepareResult = _onPrepareResult;
    ref.read(expressVpnControllerProvider).onPrepareResult = _onPrepareResult;
    final settings = ref.read(legacySettingsProvider);
    final persisted = _isExpress
        ? settings.expressVpnRunning
        : settings.vpnRunning;
    if (persisted) {
      _restoreOnLaunch =
          settings.autoStartOnLaunchEnabled &&
          settings.initialAgreementAccepted;
      // The legacy flag survives process death, so confirm with the native side.
      scheduleMicrotask(syncStatus);
      _armGuard(_launchTimeout);
      return PowerState.starting;
    }
    return PowerState.stopped;
  }

  Future<void> syncStatus() async {
    // Capture the dataset before awaiting: a concurrent switch must not write it.
    final mode = ref.read(workModeProvider);
    final express = mode == AppWorkMode.express;
    // Resolved before the await, so a mode switch cannot redirect this round trip.
    final controller = express
        ? ref.read(expressVpnControllerProvider)
        : ref.read(vpnControllerProvider);
    final settings = ref.read(legacySettingsProvider);
    // One shot, consumed even when the status call fails.
    final restore = _restoreOnLaunch;
    _restoreOnLaunch = false;
    try {
      final status = await controller.status();
      if (_disposed) return;
      if (restore &&
          !status.running &&
          !status.reclaiming &&
          ref.read(workModeProvider) == mode) {
        // The service died with the process (reboot, system kill); the user never stopped it.
        state = PowerState.stopped;
        await _start();
        return;
      }
      // While reclaiming the user still wants the tunnel; the flag drives the next launch.
      final wanted = status.running || status.reclaiming;
      if (express) {
        settings.setExpressVpnRunning(wanted);
      } else {
        settings.setVpnRunning(wanted);
      }
      if (status.error != null && !status.running) {
        lastError = status.error;
        state = PowerState.error;
      } else {
        state = status.running ? PowerState.running : PowerState.stopped;
      }
      _guardTimer?.cancel();
      ref
          .read(serviceStatsProvider.notifier)
          .applyNative(
            status.stats,
            running: status.running,
            // Server mode owns the counters there; this plane's "not running" is expected.
            ownsStats: mode != AppWorkMode.server,
            startedAt: status.startedAt,
          );
      // Keeps polling while reclaiming so the reconnect shows up without a resume.
      if (status.running || status.reclaiming) {
        _ensureStatsPolling();
      } else {
        _cancelStatsPolling();
      }
    } catch (_) {
      if (!_disposed) {
        state = PowerState.stopped;
        _guardTimer?.cancel();
      }
    }
  }

  Future<void> toggle() async {
    if (state.isBusy) return;
    if (state.isRunning) {
      await stop();
      return;
    }
    await _start();
  }

  /// Stops the tunnel; server mode calls it first so the two data planes never coexist.
  Future<void> stopIfActive() async {
    if (state.isRunning || state == PowerState.starting) {
      await stop();
    }
  }

  Future<void> _start() async {
    final mode = ref.read(workModeProvider);
    if (mode != AppWorkMode.normal && mode != AppWorkMode.express) {
      _fail(currentL10n.workModeNoDataPlane);
      return;
    }
    state = PowerState.starting;
    lastError = null;
    _armGuard(_launchTimeout);
    try {
      final prepared = await _controller.prepare();
      if (_disposed) return;
      if (!prepared) {
        // The consent dialog is showing; _onPrepareResult continues the flow.
        _pendingPermissionStart = true;
        // It can be lost on recreate or dismissal, so do not wait forever.
        _armGuard(_consentTimeout);
        return;
      }
      await _launch(mode);
    } catch (error) {
      _fail(error);
    }
  }

  /// Restarts the start watchdog; on expiry it asks the service for its real state.
  void _armGuard(Duration timeout) {
    _guardTimer?.cancel();
    _guardTimer = Timer(timeout, () {
      if (_disposed) return;
      final pending = _pendingPermissionStart;
      _pendingPermissionStart = false;
      if (state != PowerState.starting && state != PowerState.stopping) return;
      if (state == PowerState.stopping) {
        // A wedged stop: the flag is already correct, so converge to idle.
        state = PowerState.stopped;
        return;
      }
      if (pending) {
        // Consent never came back, so asking for status would hide the failure.
        _fail(currentL10n.workModeNoVpnConsent);
        return;
      }
      syncStatus().then((_) {
        if (_disposed) return;
        if (state != PowerState.starting) return;
        _fail(currentL10n.workModeStartTimeout);
      });
    });
  }

  Future<void> _onPrepareResult(bool granted) async {
    if (!_pendingPermissionStart) return;
    _pendingPermissionStart = false;
    // Consent arrived: the consent deadline is over, the launch deadline still runs.
    _armGuard(_launchTimeout);
    if (_disposed) return;
    if (!granted) {
      // Declined: a launch-time restore must not ask again on every start.
      final settings = ref.read(legacySettingsProvider);
      settings.setVpnRunning(false);
      settings.setExpressVpnRunning(false);
      state = PowerState.stopped;
      return;
    }
    try {
      await _launch(ref.read(workModeProvider));
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _launch(AppWorkMode mode) async {
    if (ref.read(workModeProvider) != mode) {
      // The user switched modes while the consent dialog was open.
      state = PowerState.stopped;
      return;
    }
    final express = mode == AppWorkMode.express;
    // One DNS config for every mode. The UI writes these keys to `dns_vpn_prefs` regardless of the
    // work mode, so reading the express dataset container here made the engine (and the
    // notification) ignore every provider/resolution change made in the app.
    final settings = ref.read(legacySettingsProvider);

    // Rules are no longer loaded or shipped here: the service builds the engine
    // snapshot in its own process (trie files + inline extras), so a large
    // subscription can no longer blow the Binder transaction limit.
    final config = buildDnsConfig(settings);
    // The service only sees the config JSON, so the body is composed here and read back from
    // prefs by the notification builder. Both VPN modes share one shape; the mode is the title.
    final statusText = defaultRunningNotificationText(settings);
    if (express) {
      settings.setNotificationDefaultExpressText(statusText);
    } else {
      settings.setNotificationDefaultRunningText(statusText);
    }
    final controller = express
        ? ref.read(expressVpnControllerProvider)
        : ref.read(vpnControllerProvider);
    final proxy = await ref.read(outboundProxyStoreProvider).read();
    if (_disposed) return;
    // A half-filled config fails validation and is dropped rather than failing the start.
    final proxyUsable = proxy.enabled && proxy.validationError() == null;
    final result = await controller.start(
      VpnStartRequest(
        dnsConfig: config.encode(settings),
        outboundProxy: proxyUsable ? proxy.toEngineJson() : '',
        // The service disallows it in the TUN so the proxy's own dials skip the tunnel.
        proxyAppPackage: proxyUsable ? proxy.proxyAppPackage : '',
        bypassLan: express ? false : settings.bypassLanEnabled,
        ipv6Mode: settings.ipv6ModeRaw,
        excludedPackages: settings.excludedPackages.toList(),
        // Express is a narrow DNS-only route, so app-level inputs are ignored.
        blockedPackages: express
            ? const []
            : settings.blockedAppPackages.toList(),
        inspectionPackages: express
            ? const []
            : settings.httpInspectionPackages.toList(),
        // 1.4.3 requires the CA before MITM may start; the transport re-checks.
        inspectionEnabled: !express && settings.httpsInspectionOperational,
      ),
    );
    if (_disposed) return;
    if (!result.started) {
      _fail(result.error ?? currentL10n.workModeVpnStartFailed);
      return;
    }
    if (express) {
      settings.setExpressVpnRunning(true);
    } else {
      settings.setVpnRunning(true);
    }
    ref.read(serviceStatsProvider.notifier).markStarted();
    state = PowerState.running;
    _guardTimer?.cancel();
    _ensureStatsPolling();
    // First counters land shortly after start; refresh once early.
    Timer(const Duration(milliseconds: 700), syncStatus);
  }

  void _ensureStatsPolling() {
    // One second: the status card shows uptime to the second, and a slower tick made the
    // figure jump in 5-second steps.
    _statsTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => syncStatus(),
    );
  }

  void _cancelStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> stop() async {
    final express = _isExpress;
    _restoreOnLaunch = false;
    _cancelStatsPolling();
    _pendingPermissionStart = false;
    state = PowerState.stopping;
    // The stop channel answers immediately; a deadline catches a wedge.
    _armGuard(_launchTimeout);
    try {
      await (express
              ? ref.read(expressVpnControllerProvider)
              : ref.read(vpnControllerProvider))
          .stop();
    } catch (error) {
      lastError = _messageOf(error);
    }
    if (_disposed) return;
    final settings = ref.read(legacySettingsProvider);
    if (express) {
      settings.setExpressVpnRunning(false);
    } else {
      settings.setVpnRunning(false);
    }
    ref.read(serviceStatsProvider.notifier).reset();
    state = PowerState.stopped;
  }

  void _fail(Object error) {
    _pendingPermissionStart = false;
    _guardTimer?.cancel();
    lastError = error is String ? error : _messageOf(error);
    final settings = ref.read(legacySettingsProvider);
    settings.setVpnRunning(false);
    settings.setExpressVpnRunning(false);
    state = PowerState.error;
  }

  static String _messageOf(Object error) => error is PlatformException
      ? (error.message ?? error.code)
      : error.toString();

  void fail() => state = PowerState.error;

  /// Pushes the current DNS settings to the running tunnel (legacy
  /// `RuntimeDnsSettingsRefresher.refreshIfRunning`); a stopped tunnel reads them on next start.
  /// Returns null when applied or nothing runs, otherwise the reason.
  Future<String?> applyDnsConfigIfRunning() async {
    if (!state.isRunning) return null;
    final settings = ref.read(legacySettingsProvider);
    final express = _isExpress;
    final statusText = defaultRunningNotificationText(settings);
    if (express) {
      settings.setNotificationDefaultExpressText(statusText);
    } else {
      settings.setNotificationDefaultRunningText(statusText);
    }
    try {
      return await _controller.applyDnsConfig(
        buildDnsConfig(settings).encode(settings),
      );
    } catch (error) {
      return _messageOf(error);
    }
  }

  void reset() => state = PowerState.stopped;
}

final powerProvider = NotifierProvider<PowerNotifier, PowerState>(
  PowerNotifier.new,
);
