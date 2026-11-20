import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesLegacyPrefsStore implements LegacyPrefsStore {
  SharedPreferencesLegacyPrefsStore(this._preferences);

  final SharedPreferences _preferences;

  static String storageKey(String container, String key) => '$container::$key';

  @override
  Map<String, Object?> readAll(String container) {
    final prefix = '$container::';
    return Map.unmodifiable({
      for (final key in _preferences.getKeys())
        if (key.startsWith(prefix)) key.substring(prefix.length): _readKey(key),
    });
  }

  Object? _readKey(String key) {
    return _preferences.get(key);
  }

  @override
  Object? read(String container, String key) =>
      _readKey(storageKey(container, key));

  @override
  void putString(String container, String key, String value) {
    _preferences.setString(storageKey(container, key), value);
  }

  @override
  void putBool(String container, String key, bool value) {
    _preferences.setBool(storageKey(container, key), value);
  }

  @override
  void putInt(String container, String key, int value) {
    _preferences.setInt(storageKey(container, key), value);
  }

  @override
  Future<void> putIntAwaiting(String container, String key, int value) async {
    await _preferences.setInt(storageKey(container, key), value);
  }

  @override
  void putLong(String container, String key, int value) {
    _preferences.setInt(storageKey(container, key), value);
  }

  @override
  void putFloat(String container, String key, double value) {
    _preferences.setDouble(storageKey(container, key), value);
  }

  @override
  void putStringSet(String container, String key, Set<String> value) {
    _preferences.setStringList(storageKey(container, key), value.toList());
  }

  @override
  void remove(String container, String key) {
    _preferences.remove(storageKey(container, key));
  }
}
