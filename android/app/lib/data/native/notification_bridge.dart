library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const notificationChannelName = 'com.haoze.diting/notification';

final notificationBridgeProvider = Provider<NotificationBridge>(
  (ref) => NotificationBridge(),
);

class NotificationBridge {
  NotificationBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(notificationChannelName);

  final MethodChannel _channel;

  Future<bool> refresh() async {
    try {
      final result = await _channel.invokeMethod<bool>('refresh');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
