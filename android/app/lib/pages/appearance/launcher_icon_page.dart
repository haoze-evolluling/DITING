library;

import 'package:diting_android/data/native/launcher_icon_bridge.dart';
import 'package:diting_android/state/launcher_icon_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class LauncherIconPage extends ConsumerWidget {
  const LauncherIconPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selected = ref.watch(launcherIconProvider);
    return CommonScaffold(
      title: l10n.launcherIconTitle,
      body: PageBody(
        children: [
          generateSection(
            title: l10n.launcherIconInfoLabel,
            items: [
              ListItem<LauncherIconStyle>.options(
                leading: const Icon(TablerIcons.photo),
                title: Text(l10n.launcherIconTitle),
                value: selected,
                options: LauncherIconStyle.values,
                textBuilder: (value) => value.label(l10n),
                onChanged: (style) async {
                  final applied = await ref
                      .read(launcherIconProvider.notifier)
                      .select(style);
                  if (!context.mounted) return;
                  showAppSnack(
                    context,
                    applied
                        ? l10n.launcherIconApplied
                        : l10n.launcherIconApplyFailed,
                    duration: const Duration(milliseconds: 1800),
                  );
                },
              ),
            ],
            footer: l10n.launcherIconFooter,
          ),
        ],
      ),
    );
  }
}
