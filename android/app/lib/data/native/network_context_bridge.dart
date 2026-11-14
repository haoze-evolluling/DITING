/// Dart side of the normalized network context (N1), `com.haoze.diting/network_profile`.
///
/// Kotlin collapses `ConnectivityManager` into the same fields `diting-netprofile-core` consumes:
/// `type` (`wifi` / `cellular` / `ethernet` / `vpn` / `none`), `metered`, `roaming`, `validated`,
/// `ssid`, `bssid`. When the channel is unavailable (widget tests, desktop) the bridge answers a
/// neutral context so the page still renders instead of throwing before the first frame.
library;

import 'package:flutter/services.dart';

class NetworkContextBridge {
  const NetworkContextBridge();

  static const _channel = MethodChannel('com.haoze.diting/network_profile');

  /// The current physical-network context; never throws.
  Future<Map<String, Object?>> context() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('context');
      if (raw == null) return _neutral;
      return Map<String, Object?>.from(raw);
    } on PlatformException {
      return _neutral;
    } on MissingPluginException {
      return _neutral;
    }
  }

  static const Map<String, Object?> _neutral = {
    'type': 'unknown',
    'metered': false,
    'roaming': false,
    'validated': false,
    'ssid': '',
    'bssid': '',
  };
}
