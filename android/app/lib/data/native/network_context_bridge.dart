library;

import 'package:flutter/services.dart';

class NetworkContextBridge {
  const NetworkContextBridge();

  static const _channel = MethodChannel('com.haoze.diting/network_profile');

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
