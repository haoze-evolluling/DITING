/// The appearance card: the palette and the day/night mode, chosen from previews.
///
/// The old desktop console's `AppearancePanel.vue` is the blueprint. The choices are the app's own
/// appearance providers, so a change here is the same change the Android appearance pages make; the
/// desktop page only lays them out as desktop cards.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/app/theme/colors.dart';
import 'package:diting/pages/appearance/mini_screen.dart';
import 'package:diting/pages/appearance/theme_page.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/state/appearance_extra_providers.dart';
import 'package:diting/state/appearance_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _tileWidth = 220;

class AppearanceThemeCard extends ConsumerWidget {
  const AppearanceThemeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = ref.watch(paletteProvider);
    final mode = ref.watch(themeModeProvider);
    final floating = ref.watch(bottomBarStyleProvider).isFloating;
    final glass = ref.watch(liquidGlassModeProvider).enabled;
    final pureBlack = ref.watch(pureBlackProvider);
    final brightness = switch (mode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final schemes = previewSchemes(seed: palette.effectiveSeed, pureBlack: pureBlack);
    Widget thumb(AppPalette option, Brightness value) => miniScreenThumb(
      colorScheme: demoColorScheme(
        seed: option.effectiveSeed,
        brightness: value,
        pureBlack: pureBlack,
      ),
      floatingBar: floating,
      liquidGlass: glass,
    );
    return DashboardCard(
      semanticLabel: l10n.desktopSettingsAppearanceTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.palette,
            title: l10n.desktopSettingsAppearanceTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopSettingsCurrent(
                  palette.label(l10n),
                  mode.label(l10n),
                ),
                tone: DashboardChipTone.idle,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopSettingsAppearanceBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.desktopSettingsPalette,
            style: DashboardText.rowTitle(context),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.desktopSettingsPaletteBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in AppPalette.values)
                SizedBox(
                  width: _tileWidth,
                  child: _PaletteTile(
                    label: option.label(l10n),
                    selected: option == palette,
                    thumbnail: thumb(option, brightness),
                    onPressed: () =>
                        ref.read(paletteProvider.notifier).select(option),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l10n.desktopSettingsMode,
            style: DashboardText.rowTitle(context),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.desktopSettingsModeBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 8),
          for (final option in AppThemeMode.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ModeTile(
                label: option.label(l10n),
                description: option == AppThemeMode.system
                    ? l10n.dayNightFollowSystemDescription
                    : null,
                selected: option == mode,
                thumbnail: switch (option) {
                  AppThemeMode.system => MiniScreenThumb(
                    screen: MiniSplitScreen(
                      light: MiniScreen(
                        colorScheme: schemes.light,
                        floatingBar: floating,
                        liquidGlass: glass,
                      ),
                      dark: MiniScreen(
                        colorScheme: schemes.dark,
                        floatingBar: floating,
                        liquidGlass: glass,
                      ),
                    ),
                  ),
                  AppThemeMode.light => thumb(palette, Brightness.light),
                  AppThemeMode.dark => thumb(palette, Brightness.dark),
                },
                onPressed: () =>
                    ref.read(themeModeProvider.notifier).select(option),
              ),
            ),
          Text(
            l10n.desktopSettingsAppearanceFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.label,
    required this.selected,
    required this.thumbnail,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final Widget thumbnail;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      isSelected: selected,
      onPressed: onPressed,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          ExcludeSemantics(child: thumbnail),
          Row(
            spacing: 6,
            children: [
              if (selected)
                GlyphIcon(
                  AppGlyphs.check,
                  size: 14,
                  color: colorScheme.primary,
                ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1.of(context, emphasized: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.description,
    required this.selected,
    required this.thumbnail,
    required this.onPressed,
  });

  final String label;
  final String? description;
  final bool selected;
  final Widget thumbnail;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      isSelected: selected,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        spacing: 10,
        children: [
          SizedBox(width: 72, child: ExcludeSemantics(child: thumbnail)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
                if (description case final description?)
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.label(context),
                  ),
              ],
            ),
          ),
          if (selected)
            GlyphIcon(AppGlyphs.check, size: 16, color: colorScheme.primary),
        ],
      ),
    );
  }
}
