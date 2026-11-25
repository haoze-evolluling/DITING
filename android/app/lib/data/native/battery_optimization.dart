library;

import 'package:flutter/services.dart';

const platformChannelName = 'com.haoze.diting/platform';

enum BatteryOptimizationState { ignored, notIgnored, unavailable }

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

Future<BatteryOptimizationState> requestBatteryOptimization() async {
  try {
    // 平台侧会等待用户从系统设置页返回后再回传授权状态。
    final granted = await const MethodChannel(platformChannelName)
        .invokeMethod<bool>('requestIgnoreBatteryOptimizations');
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
