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
}

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
