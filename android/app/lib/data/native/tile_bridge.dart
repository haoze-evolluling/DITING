/// Dart side of `com.haoze.diting/tile`: the quick settings tile opens the app with a
/// start request when it cannot start the data plane itself (no VPN consent yet, no persisted
/// start config, or server mode without a saved config).
///
/// The native side clears the extra when it is read, so a request is delivered exactly once.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const tileChannelName = 'com.haoze.diting/tile';

class TileBridge {
  TileBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(tileChannelName);

  final MethodChannel _channel;

  /// True when the tile asked for the data plane to be started. Always false when the platform
  /// side is missing (desktop, or a build without the tile).
  Future<bool> consumeStartRequest() async {
    try {
      return await _channel.invokeMethod<bool>('consumeStartRequest') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

final tileBridgeProvider = Provider<TileBridge>((ref) => TileBridge());
