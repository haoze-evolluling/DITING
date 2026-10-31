import 'dart:async';

import 'package:diting/app/theme/colors.dart';
import 'package:diting/desktop/data/desktop_backend.dart';
import 'package:diting/desktop/data/desktop_models.dart';
import 'package:diting/desktop/data/desktop_native_bridge.dart';
import 'package:diting/desktop/data/local_token_stub.dart'
    if (dart.library.js_interop) 'package:diting/desktop/data/local_token_web.dart'
    as local_token;
import 'package:diting/desktop/data/wails_bridge_stub.dart'
    if (dart.library.js_interop) 'package:diting/desktop/data/wails_bridge.dart'
    as native_bridge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final desktopPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('SharedPreferences must be loaded at startup.'),
);

final desktopBackendProvider = Provider<DesktopBackend>(
  (ref) => HttpDesktopBackend(token: local_token.readLegacyIpcToken()),
);

final desktopNativeBridgeProvider = Provider<DesktopNativeBridge>(
  (ref) => native_bridge.createDesktopNativeBridge(),
);

class DesktopThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() => AppThemeMode.fromStorageValue(
    ref.read(desktopPreferencesProvider).getString('desktop_theme_mode'),
  );

  void select(AppThemeMode mode) {
    state = mode;
    ref
        .read(desktopPreferencesProvider)
        .setString('desktop_theme_mode', mode.storageValue);
  }
}

final desktopThemeModeProvider =
    NotifierProvider<DesktopThemeModeNotifier, AppThemeMode>(
      DesktopThemeModeNotifier.new,
    );

class DesktopPaletteNotifier extends Notifier<AppPalette> {
  @override
  AppPalette build() => AppPalette.fromStorageValue(
    ref.read(desktopPreferencesProvider).getString('desktop_palette'),
  );

  void select(AppPalette palette) {
    state = palette;
    ref
        .read(desktopPreferencesProvider)
        .setString('desktop_palette', palette.storageValue);
  }
}

final desktopPaletteProvider =
    NotifierProvider<DesktopPaletteNotifier, AppPalette>(
      DesktopPaletteNotifier.new,
    );

class DesktopDashboardState {
  const DesktopDashboardState({
    this.snapshot,
    this.coreService,
    this.platform = 'windows',
    this.autoStart,
    this.nativeAvailable = false,
    this.isRefreshing = false,
    this.isActionBusy = false,
    this.lastUpdated,
    this.error,
  });

  final DesktopSnapshot? snapshot;
  final CoreServiceStatus? coreService;
  final String platform;
  final bool? autoStart;
  final bool nativeAvailable;
  final bool isRefreshing;
  final bool isActionBusy;
  final DateTime? lastUpdated;
  final String? error;

  DesktopDashboardState copyWith({
    DesktopSnapshot? snapshot,
    CoreServiceStatus? coreService,
    String? platform,
    bool? autoStart,
    bool? nativeAvailable,
    bool? isRefreshing,
    bool? isActionBusy,
    DateTime? lastUpdated,
    Object? error = _unchanged,
  }) {
    return DesktopDashboardState(
      snapshot: snapshot ?? this.snapshot,
      coreService: coreService ?? this.coreService,
      platform: platform ?? this.platform,
      autoStart: autoStart ?? this.autoStart,
      nativeAvailable: nativeAvailable ?? this.nativeAvailable,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isActionBusy: isActionBusy ?? this.isActionBusy,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      error: identical(error, _unchanged) ? this.error : error as String?,
    );
  }

  static const _unchanged = Object();
}

class DesktopDashboardNotifier extends Notifier<DesktopDashboardState> {
  Timer? _pollTimer;
  bool _refreshing = false;

  @override
  DesktopDashboardState build() {
    ref.onDispose(() => _pollTimer?.cancel());
    scheduleMicrotask(() => refresh(silent: true));
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => refresh(silent: true),
    );
    return const DesktopDashboardState(isRefreshing: true);
  }

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent) state = state.copyWith(isRefreshing: true);

    var snapshot = state.snapshot;
    var coreService = state.coreService;
    var autoStart = state.autoStart;
    var platform = state.platform;
    String? error;
    final native = ref.read(desktopNativeBridgeProvider);

    try {
      snapshot = await ref.read(desktopBackendProvider).getSnapshot();
    } on Object catch (exception) {
      error = _messageOf(exception);
    }

    if (native.isAvailable) {
      try {
        final results = await Future.wait<dynamic>([
          native.getCoreServiceStatus(),
          native.getPlatform(),
          native.isAutoStartEnabled(),
        ]);
        coreService = results[0] as CoreServiceStatus;
        platform = results[1] as String;
        autoStart = results[2] as bool;
      } on Object catch (exception) {
        error ??= _messageOf(exception);
      }
    }

    state = state.copyWith(
      snapshot: snapshot,
      coreService: coreService,
      autoStart: autoStart,
      platform: platform,
      nativeAvailable: native.isAvailable,
      isRefreshing: false,
      lastUpdated: DateTime.now(),
      error: error,
    );
    _refreshing = false;
  }

  Future<void> setDnsRunning(bool running) =>
      _perform(() => ref.read(desktopBackendProvider).setDnsRunning(running));

  Future<void> setTakeover(bool enabled) =>
      _perform(() => ref.read(desktopBackendProvider).setTakeover(enabled));

  Future<String> startCoreService() =>
      _nativeAction((native) => native.startCoreService());

  Future<String> stopCoreService() =>
      _nativeAction((native) => native.stopCoreService());

  Future<String> restartCoreService() =>
      _nativeAction((native) => native.restartCoreService());

  Future<String> installAndStartCoreService() =>
      _nativeAction((native) => native.installAndStartCoreService());

  Future<String> runEmergencyRestore() => _nativeAction(
    (native) => native.runEmergencyRestore(),
    refreshAfter: false,
  );

  Future<bool> setAutoStart(bool enabled) async {
    final native = ref.read(desktopNativeBridgeProvider);
    state = state.copyWith(isActionBusy: true);
    try {
      final result = await native.setAutoStart(enabled);
      state = state.copyWith(autoStart: result, isActionBusy: false);
      return result;
    } on Object catch (exception) {
      state = state.copyWith(isActionBusy: false, error: _messageOf(exception));
      rethrow;
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (state.isActionBusy) return;
    state = state.copyWith(isActionBusy: true);
    try {
      await action();
      await refresh(silent: true);
    } on Object catch (exception) {
      state = state.copyWith(error: _messageOf(exception));
      rethrow;
    } finally {
      state = state.copyWith(isActionBusy: false);
    }
  }

  Future<String> _nativeAction(
    Future<String> Function(DesktopNativeBridge native) action, {
    bool refreshAfter = true,
  }) async {
    final native = ref.read(desktopNativeBridgeProvider);
    state = state.copyWith(isActionBusy: true);
    try {
      final message = await action(native);
      if (refreshAfter) await refresh(silent: true);
      return message;
    } on Object catch (exception) {
      state = state.copyWith(error: _messageOf(exception));
      rethrow;
    } finally {
      state = state.copyWith(isActionBusy: false);
    }
  }

  static String _messageOf(Object error) =>
      error is DesktopBackendException ? error.message : error.toString();
}

final desktopDashboardProvider =
    NotifierProvider<DesktopDashboardNotifier, DesktopDashboardState>(
      DesktopDashboardNotifier.new,
    );
