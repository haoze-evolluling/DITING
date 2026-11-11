/// Dart side of `com.haoze.diting/launcher_icon`: the home-screen icon style.
///
/// Android cannot repaint an installed activity's icon at runtime, so the native side switches
/// between `activity-alias` components (see `LauncherIconBridge.kt` and `AndroidManifest.xml`).
/// This bridge only carries the chosen style across; every failure is non-fatal (the icon keeps
/// its previous style), so callers degrade instead of crashing.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const launcherIconChannelName = 'com.haoze.diting/launcher_icon';

/// One selectable launcher icon. [storageValue] is what preferences and the native channel use.
enum LauncherIconStyle {
  /// The DITING brand icon shipped as the default.
  standard('default'),

  /// A green shield with a white check mark.
  adguard('adguard');

  const LauncherIconStyle(this.storageValue);

  final String storageValue;

  static LauncherIconStyle fromStorageValue(String? value) => values.firstWhere(
    (style) => style.storageValue == value,
    orElse: () => standard,
  );
}

class LauncherIconBridge {
  LauncherIconBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(launcherIconChannelName);

  final MethodChannel _channel;

  /// The style currently enabled in the launcher; falls back to [LauncherIconStyle.standard] on a
  /// missing channel (desktop, tests) or an unreadable state.
  Future<LauncherIconStyle> current() async {
    try {
      final raw = await _channel.invokeMethod<String>('get');
      return LauncherIconStyle.fromStorageValue(raw);
    } on MissingPluginException {
      return LauncherIconStyle.standard;
    } on PlatformException {
      return LauncherIconStyle.standard;
    }
  }

  /// Enables [style] and retires the other aliases. False means the platform rejected the change.
  Future<bool> apply(LauncherIconStyle style) async {
    try {
      return await _channel.invokeMethod<bool>('set', {
            'style': style.storageValue,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

final launcherIconBridgeProvider = Provider<LauncherIconBridge>(
  (ref) => LauncherIconBridge(),
);
