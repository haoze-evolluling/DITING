import 'package:diting_shared/data/fonts/font_repository.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/shared_preferences_legacy_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Desktop entry point: the native Windows window (`flutter run -d windows`) and the Wails/WebView
/// host both build from here. No Android rules, tunnel channels or database bootstrap runs.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final store = SharedPreferencesLegacyPrefsStore(preferences);
  // Imported families must be registered before the first theme resolves `fontFamily`.
  await FontRepository(settings: LegacySettings(store)).registerAll();
  runApp(
    ProviderScope(
      overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
      child: const DesktopApp(),
    ),
  );
}
