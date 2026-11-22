library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const tileChannelName = 'com.haoze.diting/tile';

class TileBridge {
  TileBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(tileChannelName);

  final MethodChannel _channel;

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
