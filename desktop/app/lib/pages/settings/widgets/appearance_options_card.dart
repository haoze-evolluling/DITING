/// The appearance page's right pane: the palette gallery.
///
/// Every tile is a miniature of the window, not a swatch: the reader is picking how this app is
/// painted, so the choice is shown at the shape it will be seen at. Nine palettes at three per row
/// keep the gallery — and the pane beside it — at a height a window can show at once.
library;

import 'package:diting_desktop/pages/settings/widgets/appearance_scheme.dart';
import 'package:diting_desktop/widgets/desktop_spacing.dart';
import 'package:diting_desktop/widgets/desktop_window_preview.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Narrowest a tile may get before the gallery drops a column. At 126 the window inside is 114
/// wide, which still shows the sidebar, the toolbar and two cards apart; below that the mini window
/// is a smudge and the label is doing all the work.
const double _tileMinWidth = 126;
const double _tileGap = 12;

/// Nine palettes over four columns would leave a lone orphan in the last row; three columns fill
/// both rows evenly.
const int _maxTileColumns = 3;

class AppearanceOptionsCard extends ConsumerWidget {
  const AppearanceOptionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = ref.watch(paletteProvider);
    final mode = ref.watch(themeModeProvider);
    final pureBlack = ref.watch(pureBlackProvider);
    final brightness = appearanceBrightnessOf(context, mode);
    return DashboardCard(
      semanticLabel: l10n.desktopSettingsAppearanceTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.palette,
            title: l10n.desktopSettingsAppearanceTitle,
          ),
          const SizedBox(height: AppGap.hint),
          Text(
            l10n.desktopSettingsAppearanceBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: AppGap.lg),
          Text(
            l10n.desktopSettingsPalette,
            style: DashboardText.rowTitle(context),
          ),
          const SizedBox(height: AppGap.xxs),
          Text(
            l10n.desktopSettingsPaletteBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: AppGap.sm),
          LayoutBuilder(
            builder: (context, constraints) {
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
                      child: _PaletteTile(
                        label: option.label(l10n),
                        selected: option == palette,
                        colorScheme: appearanceColorScheme(
                          palette: option,
                          brightness: brightness,
                          pureBlack: pureBlack,
                        ),
                        onPressed: () =>
                            ref.read(paletteProvider.notifier).select(option),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppGap.lg),
          Text(
            l10n.desktopSettingsAppearanceFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

/// One palette: the window painted with it, its name under it, and a check on the tile that is in
/// use. The check sits over the preview's corner so a selected tile gains no extra height and the
/// name never shifts between the two states.
class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.label,
    required this.selected,
    required this.colorScheme,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = colorScheme.primary;
    return CommonCard(
      isSelected: selected,
      shape: AppShape.all(DashboardCorner.block).copyWith(
        side: selected
            ? BorderSide(color: primary, width: 1.5)
            : BorderSide.none,
      ),
      onPressed: onPressed,
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRSuperellipse(
                borderRadius: AppRadius.xs,
                child: ExcludeSemantics(
                  child: DesktopWindowPreview(colorScheme: colorScheme),
                ),
              ),
              if (selected)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: ShapeDecoration(
                      color: primary,
                      shape: const CircleBorder(),
                    ),
                    child: Center(
                      child: GlyphIcon(
                        AppGlyphs.check,
                        size: 11,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppGap.hint),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: DashboardText.label(context).copyWith(
              color: selected ? primary : context.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
