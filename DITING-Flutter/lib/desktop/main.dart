import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/state/desktop_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [desktopPreferencesProvider.overrideWithValue(preferences)],
      child: const DitingDesktopApp(),
    ),
  );
}
