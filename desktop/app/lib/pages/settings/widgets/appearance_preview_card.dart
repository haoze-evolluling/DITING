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

class AppearancePreviewCard extends ConsumerWidget {
  const AppearancePreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = ref.watch(paletteProvider);
    final mode = ref.watch(themeModeProvider);
    final brightness = appearanceBrightnessOf(context, mode);
    final scheme = appearanceColorScheme(
      palette: palette,
      brightness: brightness,
      pureBlack: ref.watch(pureBlackProvider),
    );
    return DashboardCard(
      semanticLabel: l10n.desktopSettingsPreview,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.devices,
            title: l10n.desktopSettingsPreview,
            leading: [
              DashboardChip(
                label: palette.label(l10n),
                tone: DashboardChipTone.idle,
              ),
              DashboardChip(
                label: appearanceModeLabel(l10n, mode, brightness),
                tone: DashboardChipTone.idle,
              ),
            ],
          ),
          const SizedBox(height: AppGap.hint),
          Text(
            l10n.desktopSettingsPreviewBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: AppGap.sm),
          DecoratedBox(
            decoration: ShapeDecoration(
              color: DashboardColors.of(context).tone2,
              shape: AppShape.standard,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppGap.sm),
              child: ExcludeSemantics(
                child: DesktopWindowPreview(colorScheme: scheme),
              ),
            ),
          ),
          const SizedBox(height: AppGap.xl),
          Text(
            l10n.desktopSettingsMode,
            style: DashboardText.rowTitle(context),
          ),
          const SizedBox(height: AppGap.xxs),
          Text(
            l10n.desktopSettingsModeBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: AppGap.sm),
          SegmentedControl<AppThemeMode>(
            segments: [
              for (final option in AppThemeMode.values)
                (option, option.label(l10n)),
            ],
            value: mode,
            onChanged: (option) =>
                ref.read(themeModeProvider.notifier).select(option),
          ),
        ],
      ),
    );
  }
}
