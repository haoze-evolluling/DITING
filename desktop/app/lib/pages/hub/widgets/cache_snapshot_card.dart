/// The two manual persistence operations: write the current cache to the file now, or read the last
/// file back.
///
/// The old desktop console's `CachePersistCard.vue` keeps these under the persistence switch; here they
/// are their own card, because they act on the file rather than configure it. A restore is confirmed
/// first: it overwrites entries that are still valid.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/data/api/desktop_cache_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CacheSnapshotCard extends ConsumerWidget {
  const CacheSnapshotCard({super.key, required this.persist});

  /// The service's persistence status; null when this build of the service does not report it.
  final DesktopCachePersist? persist;

  Future<void> _load(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopCachePersistLoadTitle,
      body: l10n.desktopCachePersistLoadBody,
      confirmLabel: l10n.desktopCachePersistLoad,
      destructive: false,
    );
    if (!confirmed || !context.mounted) return;
    final (error, persist) = await ref
        .read(desktopCacheActionProvider.notifier)
        .load();
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopCachePersistLoadDone(persist?.restored ?? 0)
          : l10n.desktopCachePersistLoadFailed(error.message),
    );
  }

  Future<void> _dump(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final (error, persist) = await ref
        .read(desktopCacheActionProvider.notifier)
        .dump();
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopCachePersistDumpDone(persist?.entryCount ?? 0)
          : l10n.desktopCachePersistDumpFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final config = ref.watch(desktopCacheConfigProvider).config;
    final action = ref.watch(desktopCacheActionProvider);
    final enabled = config?.persistEnabled ?? false;
    return DashboardCard(
      semanticLabel: l10n.desktopCacheSnapshotTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.upload,
            title: l10n.desktopCacheSnapshotTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopCachePersistRecords(
                  persist?.entryCount ?? 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopCacheSnapshotBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TonalButton(
                size: TonalButtonSize.compact,
                glyph: AppGlyphs.upload,
                label: l10n.desktopCachePersistLoad,
                onPressed: !enabled || action.isBusy
                    ? null
                    : () => unawaited(_load(context, ref)),
              ),
              TonalButton(
                size: TonalButtonSize.compact,
                glyph: AppGlyphs.bolt,
                label: l10n.desktopCachePersistDump,
                onPressed: !enabled || action.isBusy
                    ? null
                    : () => unawaited(_dump(context, ref)),
              ),
            ],
          ),
          if (action.error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.desktopActionFailed(error.message),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: context.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
