library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/site_latency_categories.dart';
import 'package:diting_android/data/site_latency_targets.dart';
import 'package:diting_android/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/state/site_latency_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class SiteLatencySitesPage extends ConsumerWidget {
  const SiteLatencySitesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIds = ref.watch(dashboardSiteIdsProvider);
    final selected = ref.watch(dashboardSitesProvider);
    final notifier = ref.read(dashboardSiteIdsProvider.notifier);
    return CommonScaffold(
      title: context.l10n.dashboardSitesTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.dashboardRestoreDefaults,
          onPressed: () => notifier.reset(),
          icon: const Icon(TablerIcons.restore),
        ),
      ],
      body: ListView(
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          ListHeader(title: context.l10n.dashboardSitesCardSection),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                for (final (index, target) in selected.indexed)
                  _SelectedRow(
                    index: index,
                    target: target,
                    onTap: () => notifier.toggle(target.id),
                  ),
                Text(
                  selectedIds.length >= dashboardSiteCount
                      ? context.l10n.dashboardSitesFull(dashboardSiteCount)
                      : context.l10n.dashboardSitesRemaining(
                          dashboardSiteCount - selectedIds.length,
                        ),
                  style: AppTextRole.micro
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          for (final category in SiteCategory.values) ...[
            ListHeader(title: category.label(context.l10n)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  for (final target in siteLatencyInCategory(category))
                    _CandidateRow(
                      target: target,
                      selected: selectedIds.contains(target.id),
                      onTap: () {
                        if (!notifier.toggle(target.id)) {
                          showAppSnack(
                            context,
                            selectedIds.contains(target.id)
                                ? context.l10n.dashboardSitesAtLeastOne
                                : context.l10n.dashboardSitesMax(
                                    dashboardSiteCount,
                                  ),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
          ListFooter(text: context.l10n.dashboardSitesFooter),
        ],
      ),
    );
  }
}

class _SelectedRow extends StatelessWidget {
  const _SelectedRow({
    required this.index,
    required this.target,
    required this.onTap,
  });

  final int index;
  final SiteLatencyTarget target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return _Tile(
      target: target,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text(
            context.l10n.dashboardSitesPosition(index + 1),
            style: AppTextRole.micro
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const Icon(TablerIcons.circle_minus, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final SiteLatencyTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return _Tile(
      target: target,
      trailing: selected
          ? Icon(
              TablerIcons.circle_check,
              size: 18,
              color: colorScheme.primary,
            )
          : const Icon(TablerIcons.circle_plus, size: 18),
      onTap: onTap,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.target,
    required this.trailing,
    required this.onTap,
  });

  final SiteLatencyTarget target;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Material(
      color: DashboardColors.of(context).card,
      shape: AppShape.standard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            spacing: 10,
            children: [
              SiteIconView(
                target.icon,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 1,
                  children: [
                    Text(
                      target.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextRole.body.of(context),
                    ),
                    Text(
                      target.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextRole.micro
                          .of(context)
                          .copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFeatures: appTabularFigures,
                          ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
