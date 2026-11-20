library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/widgets/appearance/theme_preview.dart';
import 'package:material_ui/material_ui.dart';

Brightness appearanceBrightnessOf(BuildContext context, AppThemeMode mode) =>
    switch (mode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };

ColorScheme appearanceColorScheme({
  required AppPalette palette,
  required Brightness brightness,
  required bool pureBlack,
}) => demoColorScheme(
  seed: palette.effectiveSeed,
  brightness: brightness,
  pureBlack: pureBlack,
);

String appearanceModeLabel(
  AppL10n l10n,
  AppThemeMode mode,
  Brightness brightness,
) => switch (mode) {
  AppThemeMode.system => l10n.desktopSettingsSystemResolved(
    (brightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light)
        .label(l10n),
  ),
  _ => mode.label(l10n),
};
