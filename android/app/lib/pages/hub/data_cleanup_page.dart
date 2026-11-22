import 'package:diting_android/data/cleanup/cleanup_categories.dart';
import 'package:diting_android/data/cleanup/cleanup_models.dart';
import 'package:diting_android/pages/hub/data_cleanup_common.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DataCleanupPage extends ConsumerWidget {
  const DataCleanupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(cleanupProgressProvider);
    return CommonScaffold(
      title: context.l10n.devDataCleanup,
      body: PageBody(
        children: [
          if (running != null) CleanupRunningBanner(action: running),
          generateSection(
            title: context.l10n.cleanupCategorySection,
            items: [
              for (final category in CleanupCategory.values)
                ListItem(
                  leading: Icon(_iconFor(category), size: 20),
                  title: Text(category.title(context.l10n)),
                  subtitle: Text(
                    context.l10n.cleanupCategoryItemsCount(
                      category.actions.length,
                    ),
                  ),
                  trailing: const Icon(TablerIcons.chevron_right, size: 18),
                  onTap: () =>
                      context.push(HubPaths.dataCleanupCategoryOf(category.id)),
                ),
            ],
          ),
          generateSection(
            title: context.l10n.cleanupDangerSection,
            items: [
              CleanupActionTile(
                action: CleanupAction.allData,
                enabled: running == null,
              ),
            ],
            footer: context.l10n.cleanupIntro,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static IconData _iconFor(CleanupCategory category) => switch (category) {
    CleanupCategory.runtime => TablerIcons.logs,
    CleanupCategory.weights => TablerIcons.scale,
    CleanupCategory.rules => TablerIcons.filter,
    CleanupCategory.storage => TablerIcons.database,
    CleanupCategory.guides => TablerIcons.settings,
  };
}
