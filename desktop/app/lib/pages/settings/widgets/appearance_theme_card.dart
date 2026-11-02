/// The appearance card: the palette and the day/night mode, chosen from previews.
///
/// The old desktop console's `AppearancePanel.vue` is the blueprint. The choices are the app's own
/// appearance providers, so a change here is the same change the Android appearance pages make; the
/// desktop page only lays them out as desktop cards.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/widgets/appearance/mini_screen.dart';
import 'package:diting_shared/widgets/appearance/theme_preview.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// A thumbnail is a phone-shaped preview, not a row glyph: 30 high (what the Android list rows use)
/// looks like a sliver once the tile is 200+ wide.
const double _thumbHeight = 62;
const double _tileGap = 10;

/// Narrowest a palette tile may get before the grid drops a column.
const double _tileMinWidth = 190;

/// A wide card would otherwise give each preview more empty room than the preview itself.
const int _maxTileColumns = 5;

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
    final schemes = previewSchemes(
      seed: palette.effectiveSeed,
      pureBlack: pureBlack,
    );
    Widget thumb(AppPalette option, Brightness value) => miniScreenThumb(
      colorScheme: demoColorScheme(
        seed: option.effectiveSeed,
        brightness: value,
        pureBlack: pureBlack,
      ),
      floatingBar: floating,
      liquidGlass: glass,
    );
    // The phone sits on a recessed stage so a pale light preview still reads as a screen instead of
    // melting into the tile's own tone.
    Widget preview(Widget screen) => Container(
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: DashboardColors.of(context).tone2,
        shape: AppShape.all(AppCorner.sm),
      ),
      child: ExcludeSemantics(
        child: MiniScreenThumb(screen: screen, height: _thumbHeight),
      ),
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
          const SizedBox(height: 14),
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
          LayoutBuilder(
            builder: (context, constraints) {
              // As many columns as fit the card, so the previews stay the same size on a wide
              // board instead of stretching with it.
              final columns = (constraints.maxWidth / _tileMinWidth)
                  .floor()
                  .clamp(1, _maxTileColumns);
              final tileWidth =
                  (constraints.maxWidth - _tileGap * (columns - 1)) / columns;
              return Wrap(
                spacing: _tileGap,
                runSpacing: _tileGap,
                children: [
                  for (final option in AppPalette.values)
                    SizedBox(
                      width: tileWidth,
                      child: _ChoiceTile(
                        label: option.label(l10n),
                        selected: option == palette,
                        thumbnail: preview(thumb(option, brightness)),
                        onPressed: () =>
                            ref.read(paletteProvider.notifier).select(option),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final tiles = [
                for (final option in AppThemeMode.values)
                  _ChoiceTile(
                    label: option.label(l10n),
                    description: option == AppThemeMode.system
                        ? l10n.dayNightFollowSystemDescription
                        : null,
                    selected: option == mode,
                    thumbnail: switch (option) {
                      AppThemeMode.system => preview(
                        MiniSplitScreen(
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
                      AppThemeMode.light => preview(
                        thumb(palette, Brightness.light),
                      ),
                      AppThemeMode.dark => preview(
                        thumb(palette, Brightness.dark),
                      ),
                    },
                    onPressed: () =>
                        ref.read(themeModeProvider.notifier).select(option),
                  ),
              ];
              // Three fixed choices: side by side when each tile stays wide enough for its note,
              // one per row otherwise. Stretched, so the note makes no tile taller than its row.
              if (constraints.maxWidth < 740) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: _tileGap,
                  children: tiles,
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: _tileGap,
                  children: [for (final tile in tiles) Expanded(child: tile)],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            l10n.desktopSettingsAppearanceFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

/// One choice: the preview on the left, its name (and an optional note) beside it, the check on the
/// right so the label never shifts between the two states. The selected tile is outlined and tinted
/// by its label, which keeps the preview's own colours readable.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    this.description,
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
      shape: AppShape.all(DashboardCorner.block).copyWith(
        side: selected
            ? BorderSide(color: colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        spacing: 10,
        children: [
          thumbnail,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context)
                      .copyWith(color: selected ? colorScheme.primary : null),
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
          SizedBox(
            width: 20,
            child: selected
                ? GlyphIcon(
                    AppGlyphs.check,
                    size: 16,
                    color: colorScheme.primary,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
