library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/fonts/font_repository.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fontRepositoryProvider = Provider<FontRepository>((ref) {
  return FontRepository(
    settings: ref.watch(legacySettingsProvider),
    bridge: ref.watch(platformBridgeProvider),
  );
});

final importedFontsProvider = Provider<List<ImportedFont>>((ref) {
  return ref.watch(fontRepositoryProvider).fonts;
});

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
