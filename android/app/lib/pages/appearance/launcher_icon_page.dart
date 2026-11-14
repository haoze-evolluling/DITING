/// Launcher icon picker: switches the home-screen icon between the built-in DITING mark and the
/// bundled AdGuard shield.
///
/// Android cannot repaint an installed activity's icon at runtime, so the switch flips
/// `activity-alias` components natively (`LauncherIconBridge.kt`). The choice is persisted and
/// re-applied on launch.
library;

import 'package:diting_android/data/native/launcher_icon_bridge.dart';
import 'package:diting_android/pages/appearance/appearance_shared_pages.dart'
    show showSettingHint;
import 'package:diting_android/pages/appearance/preview_choice.dart';
import 'package:diting_android/state/launcher_icon_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class LauncherIconPage extends ConsumerWidget {
  const LauncherIconPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selected = ref.watch(launcherIconProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget thumb(LauncherIconStyle style) => _IconThumb(
      asset: switch (style) {
        LauncherIconStyle.standard => dark
            ? 'packages/diting_shared/assets/images/icon_dark.webp'
            : 'packages/diting_shared/assets/images/icon.webp',
        LauncherIconStyle.adguard =>
          'packages/diting_shared/assets/images/icon_adguard.webp',
      },
    );
    return CommonScaffold(
      title: l10n.launcherIconTitle,
      body: PageBody(
        children: [
          PreviewChoiceGroup<LauncherIconStyle>(
            info: Info(label: l10n.launcherIconInfoLabel),
            value: selected,
            choices: [
              for (final style in LauncherIconStyle.values)
                PreviewChoice(
                  value: style,
                  label: style.label(l10n),
                  description: style.description(l10n),
                  pictogram: thumb(style),
                ),
            ],
            onChanged: (style) async {
              final applied = await ref
                  .read(launcherIconProvider.notifier)
                  .select(style);
              if (!context.mounted) return;
              showSettingHint(
                context,
                applied
                    ? l10n.launcherIconApplied
                    : l10n.launcherIconApplyFailed,
              );
            },
            footer: l10n.launcherIconFooter,
          ),
        ],
      ),
    );
  }
}

/// A small square preview of one launcher icon. Both assets are square and already carry the
/// brand's own rounded/squircle silhouette, so the clip only softens the corners.
class _IconThumb extends StatelessWidget {
  const _IconThumb({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(asset, width: 44, height: 44, fit: BoxFit.cover),
      ),
    );
  }
}
