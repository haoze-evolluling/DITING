/// Dart side of `com.haoze.diting/notification`: repaints the running foreground notification
/// after a setting its body is composed from changes. Kept off [PlatformBridge] because it has no
/// crash/export coupling.
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

  /// False when no service is running, which is not an error: the next start reads the change.
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
