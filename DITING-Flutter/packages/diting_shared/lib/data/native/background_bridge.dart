/// Dart side of `com.haoze.diting/background`: `pick` returns a system picker URI, `resolve`
/// decodes it to `filesDir/background/bg_<hash>.png`, `release` drops a deleted wallpaper.
library;

import 'package:flutter/services.dart';

const _backgroundChannelName = 'com.haoze.diting/background';

class BackgroundPickResult {
  const BackgroundPickResult.picked({required this.uri, required this.path})
    : cancelled = false;

  const BackgroundPickResult.cancelled()
    : uri = null,
      path = null,
      cancelled = true;

  const BackgroundPickResult.failed()
    : uri = null,
      path = null,
      cancelled = false;

  final String? uri;

  /// Decoded local cache path; null when decoding failed but the URI is valid.
  final String? path;
  final bool cancelled;

  bool get ok => uri != null;

  static BackgroundPickResult fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    if (map['cancelled'] == true) return const BackgroundPickResult.cancelled();
    final uri = map['uri'] as String?;
    if (uri == null) return const BackgroundPickResult.failed();
    return BackgroundPickResult.picked(uri: uri, path: map['path'] as String?);
  }
}

class BackgroundBridge {
  BackgroundBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_backgroundChannelName);

  final MethodChannel _channel;

  /// Opens the system image picker and caches the choice; null when cancelled.
  Future<BackgroundPickResult> pick() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('pick');
      return BackgroundPickResult.fromMap(raw);
    } on MissingPluginException {
      return const BackgroundPickResult.failed();
    } on PlatformException {
      return const BackgroundPickResult.failed();
    }
  }

  Future<String?> resolve(String uri) async {
    try {
      return await _channel.invokeMethod<String>('resolve', {'uri': uri});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> release(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>('release', {'uri': uri});
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
