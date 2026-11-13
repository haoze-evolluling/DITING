/// Dart side of `com.haoze.diting/deeplink`: a cold-start `diting://` link is pulled once with
/// [DeepLinkBridge.consumeInitialLink], a warm one is pushed through [DeepLinkBridge.listen].
///
/// The native side clears the initial link when it is read, so a request is delivered exactly once.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const deepLinkChannelName = 'com.haoze.diting/deeplink';

class DeepLinkBridge {
  DeepLinkBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(deepLinkChannelName);

  final MethodChannel _channel;
  bool _handlerInstalled = false;

  /// The link that launched the app, or null when it was not a deep link. Empty when the platform
  /// side is missing (desktop, or a build without deep links).
  Future<String?> consumeInitialLink() async {
    try {
      return await _channel.invokeMethod<String>('consumeInitialLink');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Subscribes to warm-start links. Installing the handler needs an initialized binding, so it is
  /// deferred to the caller's first build; calling twice is a no-op.
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
