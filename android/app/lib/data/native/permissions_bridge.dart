/// Dart side of `com.haoze.diting/permissions`: the runtime permissions the onboarding step and the
/// troubleshooting rows report on. Every method degrades to "unknown" instead of throwing, because
/// a missing channel is a desktop/test host, not a failure.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/services.dart';

const permissionsChannelName = 'com.haoze.diting/permissions';

/// The permissions the onboarding lists, per work mode. Names match the Kotlin `states()` keys.
enum AppPermission {
  vpn,
  notification,
  appList,
  batteryOptimization,

  /// "Display over other apps", needed by the floating log window.
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

/// One permission's reported state. [granted] is null when the channel could not answer: the UI
/// then says "unknown" rather than claiming the permission is missing.
class PermissionState {
  const PermissionState({this.granted, this.openSettingsOnly = false});

  const PermissionState.unknown() : granted = null, openSettingsOnly = false;

  final bool? granted;

  /// True when only a settings screen can change it (no runtime dialog exists on this ROM).
  final bool openSettingsOnly;

  bool get isGranted => granted == true;
  bool get isKnown => granted != null;
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

/// Real channel; [request] opens the system dialog (or the settings screen when no dialog exists)
/// and resolves with a fresh snapshot once the user is done.
class PermissionsBridge {
  PermissionsBridge({MethodChannel? channel})
    : _channel = channel ?? MethodChannel(permissionsChannelName);

  final MethodChannel _channel;

  Future<PermissionSnapshot> states() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('states');
      return PermissionSnapshot.fromMap(raw);
    } on MissingPluginException {
      return const PermissionSnapshot.unavailable();
    } on PlatformException {
      return const PermissionSnapshot.unavailable();
    }
  }

  /// Resolves with the state after the round trip; an unavailable channel answers with
  /// [PermissionSnapshot.unavailable].
  Future<PermissionSnapshot> request(AppPermission permission) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('request', {
        'permission': permission.name,
      });
      return PermissionSnapshot.fromMap(raw);
    } on MissingPluginException {
      return const PermissionSnapshot.unavailable();
    } on PlatformException {
      return const PermissionSnapshot.unavailable();
    }
  }

  /// Fallback when a request fails or the user has permanently denied the permission.
  Future<bool> openNotificationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
