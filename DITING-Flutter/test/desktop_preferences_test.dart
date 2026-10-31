import 'package:diting/data/prefs/legacy_settings.dart';
import 'package:diting/desktop/data/shared_preferences_legacy_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop store persists all legacy value types and containers', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesLegacyPrefsStore(preferences);
    final settings = LegacySettings(store);

    settings.setPaletteRaw('gold');
    settings.setPureBlackEnabled(true);
    settings.setTextScale(1.2);
    store.putLong('diting_settings', 'large', 9007199254740991);
    store.putStringSet('dns_vpn_prefs', 'tags', {'a', 'b'});

    // A new adapter over the same SharedPreferences models the next app launch.
    final restored = SharedPreferencesLegacyPrefsStore(preferences);
    final restoredSettings = LegacySettings(restored);
    expect(restoredSettings.paletteRaw, 'gold');
    expect(restoredSettings.pureBlackEnabled, isTrue);
    expect(restoredSettings.textScale, 1.2);
    expect(restored.read('diting_settings', 'large'), 9007199254740991);
    expect(restored.read('dns_vpn_prefs', 'tags'), ['a', 'b']);
    expect(restored.readAll('dns_vpn_prefs'), contains('theme_color_style'));
    expect(restored.readAll('diting_settings'), isNot(contains('theme_color_style')));

    restored.remove('dns_vpn_prefs', 'theme_color_style');
    expect(restoredSettings.paletteRaw, isNull);
  });
}
