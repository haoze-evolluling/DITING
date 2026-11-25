import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/pages/subscriptions/subscription_common.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_android/state/deep_link_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:diting_android/widgets/empty_state.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'subscriptions_cards.dart';
part 'subscriptions_groups_sheet.dart';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final localizations = UiLocalizations.of(context);
  final confirmed = await showFloatingDialog<bool>(
    context: context,
    child: CommonDialog(
      title: title,
      destructive: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(message),
    ),
  );
  return confirmed ?? false;
}

class SubscriptionsPage extends ConsumerStatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  ConsumerState<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends ConsumerState<SubscriptionsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final url = ref.read(pendingSubscriptionImportProvider);
      if (url != null) _openPendingImport(url);
    });
  }

  Future<void> _openPendingImport(String url) async {
    if (!mounted) return;
    ref.read(pendingSubscriptionImportProvider.notifier).clear();
    await context.push(SubscriptionFormPaths.addPrefilled(url));
  }

  Future<void> _updateAll() async {
    final entries = ref.read(subscriptionEntriesProvider).value ?? const [];
    final targets = [
      for (final entry in entries)
        if (entry.enabled && entry.isRemote) entry,
    ];
    if (targets.isEmpty) {
      showAppSnack(
        context,
        context.l10n.subsNothingToUpdate,
        duration: const Duration(milliseconds: 1600),
      );
      return;
    }
    await ref
        .read(subscriptionUpdateProvider.notifier)
        .updateAll(
          targets,
          confirmLarge: (_, byteLength) =>
              confirmLargeSubscription(context, byteLength),
        );
    if (!mounted) {
      return;
    }
    final message = ref.read(subscriptionUpdateProvider).lastMessage;
    if (message != null) {
      showAppSnack(
        context,
        message,
        duration: const Duration(milliseconds: 2400),
      );
    }
  }

  Future<void> _delete(SubscriptionEntry entry) async {
    final confirmed = await _confirm(
      context,
      title: context.l10n.subsDeleteTitle,
      message: context.l10n.subsDeleteMessage(entry.name),
      confirmLabel: context.l10n.commonDelete,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(subscriptionActionsProvider).remove(entry.id);
  }

  Future<void> _rename(SubscriptionEntry entry) async {
    final name = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: context.l10n.subsRenameTitle,
        value: entry.name,
        validator: (value) =>
            (value ?? '').trim().isEmpty ? context.l10n.subsNameRequired : null,
      ),
    );
    if (name != null) {
      await ref.read(subscriptionActionsProvider).rename(entry.id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingSubscriptionImportProvider, (_, url) {
      if (url != null) _openPendingImport(url);
    });
    final colorScheme = context.colorScheme;
    final asyncEntries = ref.watch(subscriptionEntriesProvider);
    final entries = asyncEntries.value ?? const <SubscriptionEntry>[];
    final groups = ref.watch(subscriptionGroupsProvider).value ?? const [];
    final groupId = ref.watch(subscriptionGroupFilterProvider);
    final selectedEntries = ref.watch(filteredSubscriptionsProvider);
    final update = ref.watch(subscriptionUpdateProvider);

    final enabledCount = entries.where((entry) => entry.enabled).length;
    final lineCount = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.ruleCount,
    );
    final failedCount = entries.where((entry) => entry.isFailed).length;
    final cachedCount = entries
        .where((entry) => entry.health == SubscriptionHealth.cached)
        .length;

    return CommonScaffold(
      title: context.l10n.subsTitle,
      isLoading: update.updatingAll,
      iconActions: [
        IconButtonData(
          glyph: TablerIcons.refresh,
          tooltip: context.l10n.subsUpdateAll,
          isLoading: update.updatingAll,
          onPressed: update.updatingAll ? null : _updateAll,
        ),
        IconButtonData(
          glyph: TablerIcons.plus,
          tooltip: context.l10n.subsAdd,
          onPressed: () => context.push(SubscriptionFormPaths.add),
        ),
        IconButtonData(
          glyph: TablerIcons.clock,
          tooltip: context.l10n.ruleVersionsTitle,
          onPressed: () => context.push(SubscriptionVersionPaths.root),
        ),
      ],
      body: SliverPageBody(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: CommonCard(
                    child: StatStrip(
                      stats: [
                        StatItem(
                          label: context.l10n.subsCount,
                          value: '${entries.length}',
                        ),
                        StatItem(
                          label: context.l10n.commonEnabled,
                          value: '$enabledCount',
                          color: colorScheme.success,
                        ),
                        StatItem(
                          label: context.l10n.subsRuleCount,
                          value: _formatCount(lineCount),
                        ),
                        if (failedCount > 0)
                          StatItem(
                            label: context.l10n.subsAbnormal,
                            value: '$failedCount',
                            color: colorScheme.destructive,
                          ),
                        if (cachedCount > 0)
                          StatItem(
                            label: context.l10n.subscriptionHealthCached,
                            value: '$cachedCount',
                            color: colorScheme.warning,
                          ),
                      ],
                    ),
                  ),
                ),
                if (asyncEntries.isLoading)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                if (update.updatingAll)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 6,
                      children: [
                        Row(
                          children: [
                            Text(
                              context.l10n.subsUpdating,
                              style: AppTextRole.supportingText.of(context),
                            ),
                            const Spacer(),
                            Text(
                              '${(update.progress * 100).round()}%',
                              style: AppTextRole.supportingText.of(context),
                            ),
                          ],
                        ),
                        LinearProgressIndicator(
                          value: update.progress,
                          minHeight: 4,
                          borderRadius: AppRadius.standard,
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _GroupChips(
                    groups: groups,
                    value: groupId,
                    totalCount: entries.length,
                    onSelect: (id) => ref
                        .read(subscriptionGroupFilterProvider.notifier)
                        .select(id),
                    onCreate: _createGroup,
                    onManage: () => showSheet<void>(
                      context: context,
                      builder: (_) => const _GroupManageSheet(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text(
                    groupId == null
                        ? context.l10n.subsTotal(entries.length)
                        : context.l10n.subsGroupTotal(
                            _groupNameOf(groups, groupId),
                            selectedEntries.length,
                          ),
                    style: AppTextRole.supportingText.of(context),
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty && !asyncEntries.isLoading)
            SliverToBoxAdapter(
              child: EmptyStateBox(
                minHeight: 300,
                child: NullStatus(
                  label: context.l10n.subsEmptyLabel,
                  description: context.l10n.subsEmptyDescription,
                  illustration: NullStatusIllustration.rules,
                  action: FilledButton(
                    onPressed: () => context.push(SubscriptionFormPaths.add),
                    child: Text(context.l10n.subsAdd),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverPrismList(
                itemCount: selectedEntries.length,
                gap: 12,
                estimatedItemExtent: 132,
                itemBuilder: (context, index) {
                  final entry = selectedEntries[index];
                  final isUpdating = update.updatingIds.contains(entry.id);
                  return MemoBuilder(
                    key: ValueKey(entry.id),
                    inputs: [entry, isUpdating, update.isBusy],
                    builder: (_) => _SubscriptionCard(
                      entry: entry,
                      isUpdating: isUpdating,
                      busy: update.isBusy,
                      onToggle: (value) => ref
                          .read(subscriptionActionsProvider)
                          .setEnabled(entry.id, value),
                      onUpdate: () => ref
                          .read(subscriptionUpdateProvider.notifier)
                          .updateOne(
                            entry.id,
                            confirmLarge: (_, byteLength) =>
                                confirmLargeSubscription(context, byteLength),
                          ),
                      onDelete: () => _delete(entry),
                      onEdit: () => _rename(entry),
                      onConfigure: () =>
                          context.push(SubscriptionFormPaths.editOf(entry.id)),
                    ),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: generateSection(
              title: context.l10n.hubModuleMore,
              items: [
                ListItem(
                  leading: const Icon(TablerIcons.refresh),
                  title: Text(context.l10n.autoUpdateTitle),
                  subtitle: Text(context.l10n.hubAutoUpdateDescription),
                  onTap: () => context.push('/hub/rules/auto-update'),
                ),
                ListItem(
                  leading: const Icon(TablerIcons.flip_horizontal),
                  title: Text(context.l10n.mirrorTplTitle),
                  subtitle: Text(context.l10n.ruleControlMirrorSubtitle),
                  onTap: () => context.push('/hub/rules/mirrors'),
                ),
                ListItem(
                  leading: const Icon(TablerIcons.user),
                  title: Text(context.l10n.customResourcesTitle),
                  subtitle: Text(context.l10n.devUserAgentBody),
                  onTap: () => context.push('/config/user-agents'),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 8, 0, 0),
              child: ListFooter(text: context.l10n.subsUpdateFooter),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createGroup() async {
    final name = await askSubscriptionGroupName(
      context,
      title: context.l10n.subsNewGroupTitle,
    );
    if (name == null) {
      return;
    }
    await ref.read(subscriptionActionsProvider).createGroup(name);
  }

  static String _groupNameOf(List<SubscriptionGroupRecord> groups, int id) {
    for (final group in groups) {
      if (group.id == id) {
        return group.name;
      }
    }
    return SubscriptionEntry.ungroupedLabel;
  }
}

class _GroupChips extends StatelessWidget {
  const _GroupChips({
    required this.groups,
    required this.value,
    required this.totalCount,
    required this.onSelect,
    required this.onCreate,
    required this.onManage,
  });

  final List<SubscriptionGroupRecord> groups;

  final int? value;
  final int totalCount;
  final ValueChanged<int?> onSelect;
  final VoidCallback onCreate;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final options = <(int?, String)>[
      (null, context.l10n.subsAllGroups),
      for (final group in groups) (group.id, group.name),
    ];
    return Row(
      children: [
        Expanded(
          child: ChipRow(
            children: [
              for (final (groupId, label) in options)
                FilterPill(
                  label: label,
                  selected: groupId == value,
                  onPressed: () => onSelect(groupId),
                ),
              TonalChip(
                label: context.l10n.subsGroupShort,
                color: context.raisedSurfaceLevel.colorOf(colorScheme),
                foregroundColor: colorScheme.onSurfaceVariant,
                onPressed: onCreate,
              ),
            ],
          ),
        ),
        if (groups.isNotEmpty)
          TextButton(
            onPressed: onManage,
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              textStyle: AppTextRole.badge.of(context),
              minimumSize: const Size(0, ChipRow.height),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                const Icon(TablerIcons.pencil, size: 16),
                Text(context.l10n.subsManageGroupsShort),
              ],
            ),
          ),
      ],
    );
  }
}

String _formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
