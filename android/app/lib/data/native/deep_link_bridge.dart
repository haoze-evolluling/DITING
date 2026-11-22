library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const deepLinkChannelName = 'com.haoze.diting/deeplink';

class DeepLinkBridge {
  DeepLinkBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(deepLinkChannelName);

  final MethodChannel _channel;
  bool _handlerInstalled = false;

  Future<String?> consumeInitialLink() async {
    try {
      return await _channel.invokeMethod<String>('consumeInitialLink');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void listen(void Function(String link) onLink) {
    if (_handlerInstalled) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final link = call.arguments;
        if (link is String && link.isNotEmpty) onLink(link);
      }
      return null;
    });
    _handlerInstalled = true;
  }
}

final deepLinkBridgeProvider = Provider<DeepLinkBridge>((ref) => DeepLinkBridge());
