library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const launcherIconChannelName = 'com.haoze.diting/launcher_icon';

enum LauncherIconStyle {
  standard('default'),

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
