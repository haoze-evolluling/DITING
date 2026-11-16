/// Access to the SharedPreferences files written by the legacy DITING app. File names and keys are
/// part of the upgrade contract, and only the platform API can open them.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const legacyPrefsChannel = MethodChannel('com.haoze.diting/legacy_prefs');

abstract class LegacyPrefsStore {
  Map<String, Object?> readAll(String container);

  Object? read(String container, String key);

  void putString(String container, String key, String value);

  void putBool(String container, String key, bool value);

  void putInt(String container, String key, int value);

  void putLong(String container, String key, int value);

  void putFloat(String container, String key, double value);

  void putStringSet(String container, String key, Set<String> value);

  void remove(String container, String key);

  /// Writes an int and completes only after the platform acknowledged it.
  ///
  /// Every other write is fire-and-forget, which is fine for UI settings: the in-memory snapshot
  /// already changed. The storage-layout marker is different — native services resolve database
  /// names from the same prefs file, so a dropped write would leave Dart on the old stores while
  /// the tunnel keeps writing the new ones. Callers use this for that one commit point only.
  Future<void> putIntAwaiting(String container, String key, int value);
}

/// Used on non-Android hosts, in tests and when the channel is unavailable.
class MemoryLegacyPrefsStore implements LegacyPrefsStore {
  MemoryLegacyPrefsStore([Map<String, Map<String, Object?>>? seed])
    : _values = {
        for (final entry in (seed ?? const {}).entries)
          entry.key: {...entry.value},
      };

  final Map<String, Map<String, Object?>> _values;

  @override
  Map<String, Object?> readAll(String container) =>
      Map.unmodifiable(_values[container] ?? const {});

  @override
  Object? read(String container, String key) => _values[container]?[key];

  void _write(String container, String key, Object? value) {
    (_values[container] ??= {})[key] = value;
  }

  @override
  void putString(String container, String key, String value) =>
      _write(container, key, value);

  @override
  void putBool(String container, String key, bool value) =>
      _write(container, key, value);

  @override
  void putInt(String container, String key, int value) =>
      _write(container, key, value);

  @override
  Future<void> putIntAwaiting(String container, String key, int value) async =>
      putInt(container, key, value);

  @override
  void putLong(String container, String key, int value) =>
      _write(container, key, value);

  @override
  void putFloat(String container, String key, double value) =>
      _write(container, key, value);

  @override
  void putStringSet(String container, String key, Set<String> value) =>
      _write(container, key, value.toList());

  @override
  void remove(String container, String key) {
    _values[container]?.remove(key);
  }
}

/// Snapshot loaded at startup; every mutation is mirrored to the real file through the channel.
class MethodChannelLegacyPrefsStore implements LegacyPrefsStore {
  MethodChannelLegacyPrefsStore(
    this._snapshot, {
    this.channel = legacyPrefsChannel,
  });

  final Map<String, Map<String, Object?>> _snapshot;
  final MethodChannel channel;

  @override
  Map<String, Object?> readAll(String container) =>
      Map.unmodifiable(_snapshot[container] ?? const {});

  @override
  Object? read(String container, String key) => _snapshot[container]?[key];

  void _write(String container, String key, String type, Object? value) {
    (_snapshot[container] ??= {})[key] = value;
    unawaited(
      channel
          .invokeMethod<void>('put', {
            'container': container,
            'key': key,
            'type': type,
            'value': value,
          })
          .catchError((Object error) {
            // A dropped write is data loss: this log is the only trace, so it must name the
            // container and key.
            debugPrint('legacy prefs write failed: $container/$key ($error)');
          }),
    );
  }

  @override
  void putString(String container, String key, String value) =>
      _write(container, key, 'string', value);

  @override
  void putBool(String container, String key, bool value) =>
      _write(container, key, 'bool', value);

  @override
  void putInt(String container, String key, int value) =>
      _write(container, key, 'int', value);

  @override
  void putLong(String container, String key, int value) =>
      _write(container, key, 'long', value);

  @override
  void putFloat(String container, String key, double value) =>
      _write(container, key, 'float', value);

  @override
  void putStringSet(String container, String key, Set<String> value) =>
      _write(container, key, 'string_set', value.toList());

  /// Acknowledged variant used for the one-time layout marker. The snapshot changes only after the
  /// platform accepted the value, so a thrown call leaves this store exactly as native sees it.
  @override
  Future<void> putIntAwaiting(String container, String key, int value) async {
    await channel.invokeMethod<void>('put', {
      'container': container,
      'key': key,
      'type': 'int',
      'value': value,
    });
    (_snapshot[container] ??= {})[key] = value;
  }

  @override
  void remove(String container, String key) {
    _snapshot[container]?.remove(key);
    unawaited(
      channel
          .invokeMethod<void>('remove', {'container': container, 'key': key})
          .catchError((Object error) {
            debugPrint('legacy prefs remove failed: $container/$key ($error)');
          }),
    );
  }
}

/// Loads every legacy container once before the first frame; without the bridge the app starts with
/// defaults. One `readAllAll` round trip replaces the twelve serial `readAll` calls that used to
/// sit on the startup path.
Future<LegacyPrefsStore> loadLegacyPrefsStore({
  MethodChannel channel = legacyPrefsChannel,
}) async {
  final snapshot = <String, Map<String, Object?>>{};
  try {
    final containers = await channel.invokeMethod<Map<Object?, Object?>>(
      'readAllAll',
    );
    for (final entry in (containers ?? const {}).entries) {
      final values = entry.value;
      if (values is! Map) continue;
      snapshot['${entry.key}'] = {
        for (final value in values.entries) '${value.key}': value.value,
      };
    }
  } on MissingPluginException {
    return MemoryLegacyPrefsStore();
  } on PlatformException catch (error) {
    debugPrint('legacy prefs load failed: $error');
    return MemoryLegacyPrefsStore();
  }
  return MethodChannelLegacyPrefsStore(snapshot, channel: channel);
}
