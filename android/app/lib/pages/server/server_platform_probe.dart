/// Probes server mode needs but `PlatformBridge` does not expose.
library;

import 'package:flutter/services.dart';

const platformChannelName = 'com.haoze.diting/platform';

const serverChannelName = 'com.haoze.diting/dns_server';

enum BatteryOptimizationState { ignored, notIgnored, unavailable }

/// Reads the battery optimization state; a missing channel yields
/// [BatteryOptimizationState.unavailable].
Future<BatteryOptimizationState> readBatteryOptimization() async {
  try {
    final granted = await const MethodChannel(platformChannelName)
        .invokeMethod<bool>('isIgnoringBatteryOptimizations');
    if (granted == null) {
      return BatteryOptimizationState.unavailable;
    }
    return granted
        ? BatteryOptimizationState.ignored
        : BatteryOptimizationState.notIgnored;
  } on MissingPluginException {
    return BatteryOptimizationState.unavailable;
  } on PlatformException {
    return BatteryOptimizationState.unavailable;
  }
}

/// Requests the system "ignore battery optimizations" prompt and returns the re-read state.
/// The native return value only means the settings page was opened, and stays true even
/// when the user cancels.
Future<BatteryOptimizationState> requestBatteryOptimization() async {
  try {
    await const MethodChannel(platformChannelName)
        .invokeMethod<bool>('requestIgnoreBatteryOptimizations');
  } on MissingPluginException {
    return BatteryOptimizationState.unavailable;
  } on PlatformException {
    return BatteryOptimizationState.unavailable;
  }
  return readBatteryOptimization();
}

/// Clears the server-mode DNS cache. A false result means nothing was cleared (service not
/// running or the engine threw), so the page must not report success.
Future<bool> clearServerDnsCache() async {
  try {
    return await const MethodChannel(serverChannelName)
            .invokeMethod<bool>('clearCache') ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
