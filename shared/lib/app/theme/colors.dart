import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Default seed colour: Apple system blue. `seededColorScheme` derives the final
/// palette from HCT, so changing this cannot break contrast assumptions.
const defaultPrimaryColor = Color(0xFF007AFF);

/// The nine palette choices on the settings page. `system` follows platform dynamic colour and
/// falls back to [defaultPrimaryColor]. `gold` keeps the legacy storage value `indigo`.
enum AppPalette {
  system('system', null),
  purple('purple', Color(0xFFAF52DE)),
  blue('blue', Color(0xFF007AFF)),
  cyan('cyan', Color(0xFF32ADE6)),
  green('green', Color(0xFF34C759)),
  orange('orange', Color(0xFFFF9500)),
  red('red', Color(0xFFFF3B30)),
  pink('pink', Color(0xFFFF2D55)),
  gold('indigo', Color(0xFFD4A017));

  const AppPalette(this.storageValue, this.seed);

  /// Display name; the strings live in the ARB resources like every other label.
  String label(AppL10n l10n) => switch (this) {
    AppPalette.system => l10n.commonFollowSystem,
    AppPalette.purple => l10n.palettePurple,
    AppPalette.blue => l10n.paletteBlue,
    AppPalette.cyan => l10n.paletteCyan,
    AppPalette.green => l10n.paletteGreen,
    AppPalette.orange => l10n.paletteOrange,
    AppPalette.red => l10n.paletteRed,
    AppPalette.pink => l10n.palettePink,
    AppPalette.gold => l10n.paletteGold,
  };

  /// Legacy `theme_color_style` value; `gold` keeps `indigo`, do not change.
  final String storageValue;

  /// Seed colour; `null` follows the system.
  final Color? seed;

  static AppPalette fromStorageValue(String? value) => values.firstWhere(
    (palette) => palette.storageValue == value,
    orElse: () => system,
  );

  /// Seed actually passed to `seededColorScheme`.
  Color get effectiveSeed => seed ?? defaultPrimaryColor;

  /// Colour used for the palette swatch; `system` needs a visible one.
  Color get swatch => seed ?? defaultPrimaryColor;

  static AppPalette fromSeed(Color color) {
    for (final palette in values) {
      if (palette.seed == color) {
        return palette;
      }
    }
    return system;
  }
}

/// Light/dark/system choice (legacy `app_theme_mode`).
enum AppThemeMode {
  system('system'),
  light('light'),
  dark('dark');

  const AppThemeMode(this.storageValue);

  String label(AppL10n l10n) => switch (this) {
    AppThemeMode.system => l10n.commonFollowSystem,
    AppThemeMode.light => l10n.themeModeLight,
    AppThemeMode.dark => l10n.themeModeDark,
  };

  /// Legacy `app_theme_mode` value.
  final String storageValue;

  static AppThemeMode fromStorageValue(String? value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => system,
  );
}
