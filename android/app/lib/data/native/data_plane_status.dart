library;

import 'package:diting_android/data/vpn/vpn_bridge.dart'
    show dataPlaneChannelNames;
import 'package:flutter/services.dart';

Future<bool> stopAllDataPlanes() async {
  for (final name in dataPlaneChannelNames) {
    try {
      await MethodChannel(name).invokeMethod<void>('stop');
    } catch (_) {
    }
  }
  for (var attempt = 0; attempt < 20; attempt++) {
    if (!await anyDataPlaneRunning()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return !await anyDataPlaneRunning();
}

Future<bool> anyDataPlaneRunning() async {
  for (final name in dataPlaneChannelNames) {
    try {
      final status = await MethodChannel(name).invokeMethod<Object?>('status');
      if (status is Map && status['running'] == true) return true;
    } catch (_) {
    }
  }
  return false;
}
