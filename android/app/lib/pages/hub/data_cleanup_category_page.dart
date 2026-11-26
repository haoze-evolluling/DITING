import 'package:diting_android/data/cleanup/cleanup_categories.dart';
import 'package:diting_android/pages/hub/data_cleanup_common.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DataCleanupCategoryPage extends ConsumerWidget {
  const DataCleanupCategoryPage({super.key, required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category =
        CleanupCategory.fromId(categoryId) ?? CleanupCategory.runtime;
    final running = ref.watch(cleanupProgressProvider);
    final active = running != null && category.actions.contains(running)
        ? running
        : null;
    return CommonScaffold(
      title: category.title(context.l10n),
      body: PageBody(
        children: [
          if (active != null) CleanupRunningBanner(action: active),
          generateSection(
            title: context.l10n.cleanupCategoryItemsSection,
            items: [
              for (final action in category.actions)
                CleanupActionTile(action: action, enabled: running == null),
            ],
            footer: context.l10n.cleanupIntro,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
