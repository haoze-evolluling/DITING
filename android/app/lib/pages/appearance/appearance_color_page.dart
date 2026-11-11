library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_android/pages/appearance/preview_choice.dart';
import 'package:diting_shared/widgets/appearance/theme_preview.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ThemeColorPage extends ConsumerWidget {
  const ThemeColorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    final pureBlack = ref.watch(pureBlackProvider);
    final floating = ref.watch(bottomBarStyleProvider).isFloating;
    final glass = ref.watch(liquidGlassModeProvider).enabled;
    final brightness = switch (ref.watch(themeModeProvider)) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    return CommonScaffold(
      title: context.l10n.appearancePaletteTitle,
      body: PageBody(
        children: [
          PreviewChoiceGroup<AppPalette>(
            info: Info(label: context.l10n.appearancePaletteInfoLabel),
            value: palette,
            choices: [
              for (final option in AppPalette.values)
                PreviewChoice(
                  value: option,
                  label: option.label(context.l10n),
                  description: option == AppPalette.gold
                      ? context.l10n.appearancePaletteGoldLegacy
                      : null,
                  pictogram: miniScreenThumb(
                    colorScheme: demoColorScheme(
                      seed: option.effectiveSeed,
                      brightness: brightness,
                      pureBlack: pureBlack,
                    ),
                    floatingBar: floating,
                    liquidGlass: glass,
                  ),
                ),
            ],
            onChanged: (value) =>
                ref.read(paletteProvider.notifier).select(value),
            footer:
                context.l10n.appearancePaletteBody,
          ),
        ],
      ),
    );
  }
}
