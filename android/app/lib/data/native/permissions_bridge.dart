library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:flutter/services.dart';

const permissionsChannelName = 'com.haoze.diting/permissions';

enum AppPermission {
  vpn,
  notification,
  appList,
  batteryOptimization,

  overlay;

  String label(AppL10n l10n) => switch (this) {
    AppPermission.vpn => l10n.permVpn,
    AppPermission.notification => l10n.permNotification,
    AppPermission.appList => l10n.permAppList,
    AppPermission.batteryOptimization => l10n.permBattery,
    AppPermission.overlay => l10n.permOverlay,
  };

  static AppPermission? fromKey(String key) {
    for (final value in values) {
      if (value.name == key) {
        return value;
      }
    }
    return null;
  }
}

class PermissionState {
  const PermissionState({this.granted, this.openSettingsOnly = false});

  const PermissionState.unknown() : granted = null, openSettingsOnly = false;

  final bool? granted;

  final bool openSettingsOnly;
}

class PermissionSnapshot {
  const PermissionSnapshot(this.states);

  const PermissionSnapshot.unavailable() : states = const {};

  final Map<AppPermission, bool> states;

  bool get available => states.isNotEmpty;

  bool? of(AppPermission permission) => states[permission];

  static PermissionSnapshot fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    final parsed = <AppPermission, bool>{};
    map.forEach((key, value) {
      if (key is! String || value is! bool) {
        return;
      }
      final permission = AppPermission.fromKey(key);
      if (permission != null) {
        parsed[permission] = value;
      }
    });
    return PermissionSnapshot(parsed);
  }
}

class PermissionsBridge {
  PermissionsBridge({MethodChannel? channel})
    : _channel = channel ?? MethodChannel(permissionsChannelName);

  final MethodChannel _channel;

  Future<PermissionSnapshot> _snapshot(
    String method, [
    Object? arguments,
  ]) async {
    try {
      return PermissionSnapshot.fromMap(
        await _channel.invokeMethod<Object?>(method, arguments),
      );
    } on MissingPluginException {
      return const PermissionSnapshot.unavailable();
    } on PlatformException {
      return const PermissionSnapshot.unavailable();
    }
  }

  Future<bool> _flag(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<PermissionSnapshot> states() => _snapshot('states');

  Future<PermissionSnapshot> request(AppPermission permission) =>
      _snapshot('request', {'permission': permission.name});

  Future<bool> openNotificationSettings() => _flag('openNotificationSettings');

  Future<bool> openAppSettings() => _flag('openAppSettings');
}
