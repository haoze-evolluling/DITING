import 'package:diting_android/app/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

const defaultPrimaryColor = Color(0xFF007AFF);

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

  final String storageValue;

  final Color? seed;

  static AppPalette fromStorageValue(String? value) => values.firstWhere(
    (palette) => palette.storageValue == value,
    orElse: () => system,
  );

  Color get effectiveSeed => seed ?? defaultPrimaryColor;

  static AppPalette fromSeed(Color color) {
    for (final palette in values) {
      if (palette.seed == color) {
        return palette;
      }
    }
    return system;
  }
}

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

  final String storageValue;

  static AppThemeMode fromStorageValue(String? value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => system,
  );
}
