import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/mirror_template_repository.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/subscriptions/subscription_url.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_android/state/deep_link_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:diting_android/widgets/empty_state.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'subscriptions_cards.dart';
part 'subscriptions_groups_sheet.dart';
part 'subscriptions_sheet.dart';
part 'subscriptions_sheet_widgets.dart';

/// Subscriptions page: group filter, summary and card list. Groups sit at the top because
/// users usually watch one group; data comes from the legacy `subscription_group` table
/// ordered by `addedAt`.
class SubscriptionsPage extends ConsumerStatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  ConsumerState<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends ConsumerState<SubscriptionsPage> {
  @override
  void initState() {
    super.initState();
    // The deep link set the pending address before navigating here, so the initial value is not a
    // state change `ref.listen` would report; read it once after the first frame instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final url = ref.read(pendingSubscriptionImportProvider);
      if (url != null) _openPendingImport(url);
    });
  }

  /// Opens the add-subscription sheet with the deep-linked address filled in.
  Future<void> _openPendingImport(String url) async {
    if (!mounted) return;
    ref.read(pendingSubscriptionImportProvider.notifier).clear();
    await showSheet<void>(
      context: context,
      builder: (_) => _AddSubscriptionSheet(prefillUrl: url),
    );
  }

  Future<void> _updateAll(BuildContext context, WidgetRef ref) async {
    final entries = ref.read(subscriptionEntriesProvider).value ?? const [];
    final targets = [
      for (final entry in entries)
        if (entry.enabled && entry.isRemote) entry,
    ];
    if (targets.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.subsNothingToUpdate),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1600),
        ),
      );
      return;
    }
    await ref.read(subscriptionUpdateProvider.notifier).updateAll(targets);
    if (!context.mounted) {
      return;
    }
    final message = ref.read(subscriptionUpdateProvider).lastMessage;
    if (message != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2400),
        ),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SubscriptionEntry entry,
  ) async {
    final localizations = UiLocalizations.of(context);
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.subsDeleteTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(
          context.l10n.subsDeleteMessage(entry.name),
        ),
      ),
    );
    if (confirmed ?? false) {
      await ref.read(subscriptionActionsProvider).remove(entry.id);
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    SubscriptionEntry entry,
  ) async {
    final name = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: context.l10n.subsRenameTitle,
        value: entry.name,
        validator: (value) => (value ?? '').trim().isEmpty ? context.l10n.subsNameRequired : null,
      ),
    );
    if (name != null) {
      await ref.read(subscriptionActionsProvider).rename(entry.id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A link that arrives while this page is already mounted changes the provider instead.
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
          glyph: AppGlyphs.refresh,
          tooltip: context.l10n.subsUpdateAll,
          isLoading: update.updatingAll,
          onPressed: update.updatingAll ? null : () => _updateAll(context, ref),
        ),
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.subsAdd,
          onPressed: () => showSheet<void>(
            context: context,
            builder: (_) => const _AddSubscriptionSheet(),
          ),
        ),
        IconButtonData(
          glyph: AppGlyphs.clock,
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
                        StatItem(label: context.l10n.subsCount, value: '${entries.length}'),
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
                            Text(context.l10n.subsUpdating, style: context.listCaptionStyle),
                            const Spacer(),
                            Text(
                              '${(update.progress * 100).round()}%',
                              style: context.listCaptionStyle,
                            ),
                          ],
                        ),
                        LinearProgressIndicator(
                          value: update.progress,
                          minHeight: 4,
                          borderRadius: AppRadius.full,
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
                    onCreate: () => _createGroup(context, ref),
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
                    style: context.listCaptionStyle,
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty && !asyncEntries.isLoading)
            SliverToBoxAdapter(
              // Minimum height only, never a fixed 300: the description wraps to two lines
              // and the button sits below, so a fixed height clips them.
              child: EmptyStateBox(
                minHeight: 300,
                child: NullStatus(
                  label: context.l10n.subsEmptyLabel,
                  description:
                      context.l10n.subsEmptyDescription,
                  illustration: NullStatusIllustration.rules,
                  action: FilledButton(
                    onPressed: () => showSheet<void>(
                      context: context,
                      builder: (_) => const _AddSubscriptionSheet(),
                    ),
                    child: Text(context.l10n.subsAdd),
                  ),
                ),
              ),
            )
          else
            // Lazily built cards: one card per subscription, and the list grows with every
            // import, so building all of them up front stalls the page the same way bulk rule
            // tables did.
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
                          .updateOne(entry.id),
                      onDelete: () => _delete(context, ref, entry),
                      onEdit: () => _rename(context, ref, entry),
                      onConfigure: () => showSheet<void>(
                        context: context,
                        builder: (_) => _AddSubscriptionSheet(initial: entry),
                      ),
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
                  leading: const GlyphIcon(AppGlyphs.refresh),
                  title: Text(context.l10n.autoUpdateTitle),
                  subtitle: Text(context.l10n.hubAutoUpdateDescription),
                  onTap: () => context.push('/hub/rules/auto-update'),
                ),
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.layers),
                  title: Text(context.l10n.mirrorTplTitle),
                  subtitle: Text(context.l10n.ruleControlMirrorSubtitle),
                  onTap: () => context.push('/hub/rules/mirrors'),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 8, 0, 0),
              child: ListFooter(
                text:
                    context.l10n.subsUpdateFooter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final name = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: context.l10n.subsNewGroupTitle,
        value: '',
        validator: (value) => (value ?? '').trim().isEmpty ? context.l10n.subsGroupNameRequired : null,
      ),
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
              // The create chip is a management entry, not a filter, so it is never selected.
              TonalChip(
                label: context.l10n.subsGroupShort,
                color: context.raisedSurfaceLevel.colorOf(colorScheme),
                foregroundColor: colorScheme.onSurfaceVariant,
                onPressed: onCreate,
              ),
            ],
          ),
        ),
        // Pinned outside the scrolling row: group management must stay reachable no matter how
        // many groups push the chips off-screen.
        if (groups.isNotEmpty)
          TextButton(
            onPressed: onManage,
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              textStyle: AppTextStyle.caption1.of(context, emphasized: true),
              minimumSize: const Size(0, ChipRow.height),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                const GlyphIcon(AppGlyphs.edit, size: 16),
                Text(context.l10n.subsManageGroupsShort),
              ],
            ),
          ),
      ],
    );
  }
}

/// Thousands separators: the rule count is the only large number here and `48,213` reads
/// faster than `48213`.
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
