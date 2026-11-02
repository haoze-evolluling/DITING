/// The subscription lists: a counters strip, the add/refresh actions and one tile per list with its
/// health, its last pull and the three per-row actions.
///
/// The old desktop console's `RuleListsPanel.vue` is the blueprint. The page never edits a rule
/// count or a health badge by hand: it sends the write and shows the rows the service answers with.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_filter_models.dart';
import 'package:diting_desktop/data/api/desktop_filter_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_list_dialog.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Two tiles appear once two still fit their URL and footer; below this they stack.
const double _twoColumnBreakpoint = 900;

/// The counters above the lists: what the engine blocked, how large it is and how many lists are on.
class FilterSummaryCard extends StatelessWidget {
  const FilterSummaryCard({
    super.key,
    required this.summary,
    this.onToggle,
    this.saving = false,
  });

  final DesktopFilterSummary summary;

  /// The master switch; only the page that owns the config write path passes it.
  final ValueChanged<bool>? onToggle;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopFilterSummaryTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.rules,
            title: l10n.desktopFilterSummaryTitle,
            leading: [
              DashboardChip(
                label: summary.enabled
                    ? l10n.desktopFilterEngineOn
                    : l10n.desktopFilterEngineOff,
                tone: summary.enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: true,
              ),
              if (summary.paused)
                DashboardChip(
                  label: l10n.desktopFilterPausedChip,
                  tone: DashboardChipTone.warn,
                ),
            ],
            trailing: [
              if (onToggle case final toggle?)
                DashboardSwitch(
                  value: summary.enabled,
                  semanticLabel: l10n.desktopFilterSummaryTitle,
                  onChanged: saving ? null : toggle,
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = [
                FilterMetric(
                  label: l10n.desktopFilterBlocked,
                  value: dashboardCount(summary.blocked),
                  unit: l10n.desktopFilterTimes,
                ),
                FilterMetric(
                  label: l10n.desktopFilterBlockRate,
                  value: (summary.blockRate * 100).toStringAsFixed(1),
                  unit: '%',
                ),
                FilterMetric(
                  label: l10n.desktopFilterRules,
                  value: dashboardCount(summary.rules),
                  unit: l10n.desktopFilterRulesUnit,
                ),
                FilterMetric(
                  label: l10n.desktopFilterActiveLists,
                  value: dashboardCount(summary.activeLists),
                  unit: l10n.desktopFilterListsUnit,
                ),
              ];
              if (constraints.maxWidth < 560) {
                return Wrap(spacing: 20, runSpacing: 12, children: metrics);
              }
              return Row(
                spacing: 16,
                children: [
                  for (final metric in metrics) Expanded(child: metric),
                ],
              );
            },
          ),
          if (summary.paused) ...[
            const SizedBox(height: 10),
            Text(
              l10n.desktopFilterPausedRemaining(
                desktopPauseRemaining(context, summary.pausedRemaining),
              ),
              style: DashboardText.label(
                context,
                color: colorScheme.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The list itself: header actions, the empty state and the tiles.
class FilterListsCard extends ConsumerWidget {
  const FilterListsCard({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final draft = await showAddFilterListDialog(context);
    if (draft == null || !context.mounted) return;
    final name = draft.name.isEmpty
        ? l10n.desktopFilterListDefaultName(
            ref.read(desktopFilterListsProvider).lists.total + 1,
          )
        : draft.name;
    final error = await ref
        .read(desktopFilterListsProvider.notifier)
        .add(name: name, url: draft.url);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopFilterListAdded
          : l10n.desktopFilterActionFailed(error.message),
    );
  }

  Future<void> _refreshAll(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopFilterListsProvider.notifier)
        .refresh('');
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopFilterListAllUpdated
          : l10n.desktopFilterActionFailed(error.message),
    );
  }

  Future<void> _refreshOne(
    BuildContext context,
    WidgetRef ref,
    DesktopFilterList list,
  ) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopFilterListsProvider.notifier)
        .refresh(list.id);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopFilterListUpdated
          : l10n.desktopFilterActionFailed(error.message),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    DesktopFilterList list,
    bool enabled,
  ) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopFilterListsProvider.notifier)
        .setEnabled(list, enabled);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (enabled
                ? l10n.desktopFilterListToggleOn(list.name)
                : l10n.desktopFilterListToggleOff(list.name))
          : l10n.desktopFilterActionFailed(error.message),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    DesktopFilterList list,
  ) async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopFilterListDeleteTitle,
      body: l10n.desktopFilterListDeleteBody(list.name),
      confirmLabel: l10n.desktopFilterListDeleteConfirm,
    );
    if (!confirmed || !context.mounted) return;
    final error = await ref
        .read(desktopFilterListsProvider.notifier)
        .delete(list.id);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopFilterListDeleted
          : l10n.desktopFilterActionFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopFilterListsProvider);
    final lists = state.lists.lists;
    return DashboardCard(
      semanticLabel: l10n.desktopFilterListsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.rules,
            title: l10n.desktopFilterListsTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopFilterListsCount(state.lists.total),
              ),
            ],
            trailing: [
              if (state.busyId == allListsBusy)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardIconButton(
                  glyph: AppGlyphs.sync,
                  tooltip: l10n.desktopFilterListUpdateAll,
                  onPressed: state.saving
                      ? null
                      : () => unawaited(_refreshAll(context, ref)),
                ),
              DashboardIconButton(
                glyph: AppGlyphs.add,
                tooltip: l10n.desktopFilterListAdd,
                onPressed: state.saving
                    ? null
                    : () => unawaited(_add(context, ref)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopFilterListsBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (lists.isEmpty)
            _Empty(
              onAdd: state.saving
                  ? null
                  : () => unawaited(_add(context, ref)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final tiles = [
                  for (final list in lists)
                    _FilterListTile(
                      list: list,
                      saving: state.saving,
                      refreshing: state.isBusy(list.id),
                      onToggle: (value) =>
                          unawaited(_toggle(context, ref, list, value)),
                      onRefresh: () =>
                          unawaited(_refreshOne(context, ref, list)),
                      onDelete: () =>
                          unawaited(_delete(context, ref, list)),
                    ),
                ];
                if (constraints.maxWidth < _twoColumnBreakpoint) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: tiles,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    for (var index = 0; index < tiles.length; index += 2)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 10,
                        children: [
                          Expanded(child: tiles[index]),
                          Expanded(
                            child: index + 1 < tiles.length
                                ? tiles[index + 1]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        spacing: 6,
        children: [
          GlyphIcon(
            AppGlyphs.rules,
            size: 28,
            color: colorScheme.onSurfaceVariant,
          ),
          Text(l10n.desktopFilterListsEmpty, style: DashboardText.rowTitle(context)),
          Text(
            l10n.desktopFilterListsEmptyBody,
            textAlign: TextAlign.center,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const GlyphIcon(AppGlyphs.add, size: 16),
            label: Text(l10n.desktopFilterListAdd),
          ),
        ],
      ),
    );
  }
}

class _FilterListTile extends StatelessWidget {
  const _FilterListTile({
    required this.list,
    required this.saving,
    required this.refreshing,
    required this.onToggle,
    required this.onRefresh,
    required this.onDelete,
  });

  final DesktopFilterList list;
  final bool saving;
  final bool refreshing;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final health = desktopFilterHealthLabel(context, list);
    final updated = list.lastUpdated;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              GlyphIcon(
                AppGlyphs.rules,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              Expanded(
                child: Text(
                  list.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
              ),
              DashboardChip(
                label: l10n.desktopFilterListRules(list.rulesCount),
              ),
              DashboardSwitch(
                value: list.enabled,
                semanticLabel: list.name,
                onChanged: saving ? null : onToggle,
              ),
            ],
          ),
          Text(
            list.enabled
                ? l10n.desktopFilterListEnabled
                : l10n.desktopFilterListDisabled,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: ShapeDecoration(
              color: DashboardColors.of(context).tone2,
              shape: AppShape.all(AppCorner.sm),
            ),
            child: Text(
              list.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context).toMonospace,
            ),
          ),
          if (list.lastError.isNotEmpty)
            Text(
              list.lastError,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(
                context,
                color: colorScheme.warning,
              ),
            ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  updated == null
                      ? l10n.desktopFilterListNeverUpdated
                      : l10n.desktopFilterListUpdatedAt(
                          desktopMonthDayTime(updated),
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ),
              if (health.isNotEmpty)
                Tooltip(
                  message: desktopFilterHealthDetail(context, list),
                  child: DashboardChip(
                    label: health,
                    tone: desktopFilterHealthTone(list),
                  ),
                ),
              if (refreshing)
                const SizedBox.square(
                  dimension: 14,
                  child: CommonCircleLoading(),
                )
              else
                SizedBox(
                  height: 28,
                  child: DashboardIconButton(
                    glyph: AppGlyphs.refresh,
                    tooltip: l10n.desktopFilterListRefreshOne,
                    size: 28,
                    glyphSize: 16,
                    onPressed: saving ? null : onRefresh,
                  ),
                ),
              SizedBox(
                height: 28,
                child: DashboardIconButton(
                  glyph: AppGlyphs.delete,
                  tooltip: l10n.desktopFilterListDelete,
                  size: 28,
                  glyphSize: 16,
                  onPressed: saving ? null : onDelete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
