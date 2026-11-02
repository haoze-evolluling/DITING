/// Imported-font state: the repository plus the list the settings pages render.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/fonts/font_repository.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Font import/delete and engine registration; the native channel folds failures into results.
final fontRepositoryProvider = Provider<FontRepository>((ref) {
  return FontRepository(
    settings: ref.watch(legacySettingsProvider),
    bridge: ref.watch(platformBridgeProvider),
  );
});

/// Imported fonts, refreshed whenever the repository rebuilds after a settings write.
final importedFontsProvider = Provider<List<ImportedFont>>((ref) {
  return ref.watch(fontRepositoryProvider).fonts;
});

/// Display label for a `fontFamily` value: the imported font's file name, else "系统默认".
String fontLabelOf(List<ImportedFont> fonts, String? family) {
  if (family == null) {
    return currentL10n.fontSystemDefault;
  }
  for (final font in fonts) {
    if (font.family == family) {
      return font.label;
    }
  }
  return family;
}
