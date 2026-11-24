part of 'work_mode_providers.dart';

class PowerNotifier extends Notifier<PowerState> {
  static const Duration _consentTimeout = Duration(seconds: 90);

  static const Duration _launchTimeout = Duration(seconds: 30);

  bool _disposed = false;
  bool _pendingPermissionStart = false;

  bool _restoreOnLaunch = false;
  Timer? _statsTimer;
  Timer? _uptimeTimer;
  Timer? _guardTimer;

  String? lastError;

  bool get _isExpress => ref.read(workModeProvider) == AppWorkMode.express;

  /// Root 免 VPN 接管优先于 VPN 隧道：普通与简洁模式都可用。
  bool get _isRoot =>
      ref.read(workModeProvider).hasTunnelFeatures &&
      ref.read(rootDnsTakeoverProvider);

  VpnController get _controller => _isRoot
      ? ref.read(rootDnsControllerProvider)
      : _isExpress
      ? ref.read(expressVpnControllerProvider)
      : ref.read(vpnControllerProvider);

  @override
  PowerState build() {
    ref.onDispose(() {
      _disposed = true;
      _statsTimer?.cancel();
      _uptimeTimer?.cancel();
      _guardTimer?.cancel();
    });
    ref.read(vpnControllerProvider).onPrepareResult = _onPrepareResult;
    ref.read(expressVpnControllerProvider).onPrepareResult = _onPrepareResult;
    final settings = ref.read(legacySettingsProvider);
    final persisted = _isRoot
        ? settings.rootDnsRunning
        : _isExpress
        ? settings.expressVpnRunning
        : settings.vpnRunning;
    if (persisted) {
      _restoreOnLaunch =
          settings.autoStartOnLaunchEnabled &&
          settings.initialAgreementAccepted;
      scheduleMicrotask(syncStatus);
      _armGuard(_launchTimeout);
      return PowerState.starting;
    }
    return PowerState.stopped;
  }

  Future<void> syncStatus() async {
    final mode = ref.read(workModeProvider);
    final root = mode.hasTunnelFeatures && ref.read(rootDnsTakeoverProvider);
    final express = mode == AppWorkMode.express && !root;
    final controller = root
        ? ref.read(rootDnsControllerProvider)
        : express
        ? ref.read(expressVpnControllerProvider)
        : ref.read(vpnControllerProvider);
    final settings = ref.read(legacySettingsProvider);
    final restore = _restoreOnLaunch;
    _restoreOnLaunch = false;
    try {
      final status = await controller.status();
      if (_disposed) return;
      if (restore &&
          !status.running &&
          !status.starting &&
          !status.reclaiming &&
          ref.read(workModeProvider) == mode) {
        state = PowerState.stopped;
        await _start();
        return;
      }
      final starting = status.starting && !status.running;
      final wanted = status.running || status.reclaiming || starting;
      if (root) {
        settings.setRootDnsRunning(wanted);
      } else if (express) {
        settings.setExpressVpnRunning(wanted);
      } else {
        settings.setVpnRunning(wanted);
      }
      if (status.error != null && !status.running) {
        lastError = status.error;
        state = PowerState.error;
      } else if (status.running) {
        state = PowerState.running;
      } else if (starting) {
        state = PowerState.starting;
      } else {
        state = PowerState.stopped;
      }
      if (!starting) _guardTimer?.cancel();
      ref
          .read(serviceStatsProvider.notifier)
          .applyNative(
            status.stats,
            running: status.running,
            startedAt: status.startedAt,
          );
      if (status.running || status.reclaiming || starting) {
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

  Future<void> _start() async {
    final mode = ref.read(workModeProvider);
    state = PowerState.starting;
    lastError = null;
    _armGuard(_launchTimeout);
    try {
      final prepared = await _controller.prepare();
      if (_disposed) return;
      if (!prepared) {
        _pendingPermissionStart = true;
        _armGuard(_consentTimeout);
        return;
      }
      await _launch(mode);
    } catch (error) {
      _fail(error);
    }
  }

  void _armGuard(Duration timeout) {
    _guardTimer?.cancel();
    _guardTimer = Timer(timeout, () {
      if (_disposed) return;
      final pending = _pendingPermissionStart;
      _pendingPermissionStart = false;
      if (state != PowerState.starting && state != PowerState.stopping) return;
      if (state == PowerState.stopping) {
        state = PowerState.stopped;
        return;
      }
      if (pending) {
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
    _armGuard(_launchTimeout);
    if (_disposed) return;
    if (!granted) {
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
      state = PowerState.stopped;
      return;
    }
    final root = mode.hasTunnelFeatures && ref.read(rootDnsTakeoverProvider);
    final express = mode == AppWorkMode.express;
    final settings = ref.read(legacySettingsProvider);

    final config = buildDnsConfig(settings);
    final statusText = defaultRunningNotificationText(settings);
    if (express) {
      settings.setNotificationDefaultExpressText(statusText);
    } else {
      settings.setNotificationDefaultRunningText(statusText);
    }
    final controller = root
        ? ref.read(rootDnsControllerProvider)
        : express
        ? ref.read(expressVpnControllerProvider)
        : ref.read(vpnControllerProvider);
    if (root) {
      final result = await controller.start(
        VpnStartRequest(dnsConfig: buildDnsConfig(settings).encode(settings)),
      );
      if (_disposed) return;
      if (!result.started) {
        _fail(result.error ?? currentL10n.workModeVpnStartFailed);
        return;
      }
      settings.setRootDnsRunning(true);
      state = PowerState.starting;
      _ensureStatsPolling();
      Timer(const Duration(milliseconds: 700), syncStatus);
      return;
    }
    final proxy = await ref.read(outboundProxyStoreProvider).read();
    if (_disposed) return;
    final proxyUsable = proxy.enabled && proxy.validationError() == null;
    final result = await controller.start(
      VpnStartRequest(
        dnsConfig: config.encode(settings),
        outboundProxy: proxyUsable ? proxy.toEngineJson() : '',
        proxyAppPackage: proxyUsable ? proxy.proxyAppPackage : '',
        bypassLan: settings.bypassLanEnabled,
        ipv6Mode: settings.ipv6Mode.storageValue,
        routeAddress: settings.vpnRouteAddress,
        routeExcludeAddress: settings.vpnRouteExcludeAddress,
        excludedPackages: settings.excludedPackages.toList(),
        blockedPackages: settings.blockedAppPackages.toList(),
        inspectionPackages: settings.httpInspectionPackages.toList(),
        inspectionEnabled: settings.httpsInspectionOperational,
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
    Timer(const Duration(milliseconds: 700), syncStatus);
  }

  void _ensureStatsPolling() {
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

  Future<void> stop() async {
    final express = _isExpress;
    final root = _isRoot;
    _restoreOnLaunch = false;
    _cancelStatsPolling();
    _pendingPermissionStart = false;
    state = PowerState.stopping;
    _armGuard(_launchTimeout);
    try {
      await _controller.stop();
    } catch (error) {
      lastError = _messageOf(error);
    }
    if (_disposed) return;
    final settings = ref.read(legacySettingsProvider);
    if (root) {
      settings.setRootDnsRunning(false);
    } else if (express) {
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
    settings.setRootDnsRunning(false);
    state = PowerState.error;
  }

  static String _messageOf(Object error) => error is PlatformException
      ? (error.message ?? error.code)
      : error.toString();

  void fail() => state = PowerState.error;

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
