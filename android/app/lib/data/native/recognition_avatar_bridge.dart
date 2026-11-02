/// On-disk avatar cache for the roster (`com.haoze.diting/recognition`). Avatars ship outside the
/// APK, so caching avoids a refetch per cold start; Kotlin writes via `.part` + `renameTo`, and a
/// missing channel degrades to "no cache".
library;

import 'package:flutter/services.dart';

const _recognitionChannelName = 'com.haoze.diting/recognition';

class RecognitionAvatarBridge {
  const RecognitionAvatarBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_recognitionChannelName);

  final MethodChannel _channel;

  Future<Uint8List?> read(String name) async {
    try {
      return await _channel.invokeMethod<Uint8List>('read', {'name': name});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> write(String name, Uint8List bytes) async {
    try {
      final path = await _channel.invokeMethod<String>('write', {
        'name': name,
        'bytes': bytes,
      });
      return path != null;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<int> clear() async {
    try {
      return await _channel.invokeMethod<int>('clear') ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }
}
