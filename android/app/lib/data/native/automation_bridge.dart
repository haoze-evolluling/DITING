library;

import 'package:flutter/services.dart';

const automationChannelName = 'com.haoze.diting/automation';

class AutomationBridge {
  AutomationBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(automationChannelName);

  final MethodChannel _channel;

  Future<void> reschedule() async {
    try {
      await _channel.invokeMethod<bool>('reschedule');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<int> runNow({String eventType = 'manual'}) async {
    try {
      final applied = await _channel.invokeListMethod<String>('runNow', {
        'eventType': eventType,
      });
      return applied?.length ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }
}
