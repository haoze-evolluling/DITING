/// Whether a tunnel or the LAN DNS service is alive in this process.
///
/// The persisted "running" flags survive a force-stop, so storage work asks the native status
/// calls instead. Shared by startup (the migration must not fork the log files) and by the
/// developer storage actions.
library;

import 'package:diting_android/data/vpn/vpn_bridge.dart'
    show vpnChannelName, expressVpnChannelName, dnsServerChannelName;
import 'package:flutter/services.dart';

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
