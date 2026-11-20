import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/shared_preferences_legacy_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final store = SharedPreferencesLegacyPrefsStore(preferences);
  runApp(
    ProviderScope(
      overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
      child: const DesktopApp(),
    ),
  );
}
