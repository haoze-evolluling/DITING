/// Whether a tunnel or the LAN DNS service is alive in this process.
///
/// The persisted "running" flags survive a force-stop, so storage work asks the native status
/// calls instead. Shared by startup (the migration must not fork the log files) and by the
/// developer storage actions.
library;

import 'package:diting_android/data/vpn/vpn_bridge.dart'
    show vpnChannelName, expressVpnChannelName, dnsServerChannelName;
import 'package:flutter/services.dart';

/// Asks every tunnel-like service to stop and waits briefly for the native state to settle.
Future<bool> stopAllDataPlanes() async {
  for (final name in const [
    vpnChannelName,
    expressVpnChannelName,
    dnsServerChannelName,
  ]) {
    try {
      await MethodChannel(name).invokeMethod<void>('stop');
    } catch (_) {
      // A stopped or unavailable service has nothing to stop.
    }
  }
  for (var attempt = 0; attempt < 20; attempt++) {
    if (!await anyDataPlaneRunning()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return !await anyDataPlaneRunning();
}

Future<bool> anyDataPlaneRunning() async {
  for (final name in const [
    vpnChannelName,
    expressVpnChannelName,
    dnsServerChannelName,
  ]) {
    try {
      final status = await MethodChannel(name).invokeMethod<Object?>('status');
      if (status is Map && status['running'] == true) return true;
    } catch (_) {
      // No native channel (desktop/tests) or the service is stopped.
    }
  }
  return false;
}
