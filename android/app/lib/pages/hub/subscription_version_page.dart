/// R6: subscription rule-set version history, diff preview and rollback.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/rule_version_repository.dart';
import 'package:diting_android/data/rules/rule_importer.dart';
import 'package:diting_android/data/rules/rule_parser.dart';
import 'package:diting_android/data/rules/rust_rule_version_core.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/page_intro.dart';

class SubscriptionVersionPage extends ConsumerStatefulWidget {
  const SubscriptionVersionPage({super.key});

  @override
  ConsumerState<SubscriptionVersionPage> createState() =>
      _SubscriptionVersionPageState();
}

class _SubscriptionVersionPageState
    extends ConsumerState<SubscriptionVersionPage> {
  int? _selectedId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entriesAsync = ref.watch(subscriptionEntriesProvider);
    return CommonScaffold(
      title: l10n.ruleVersionsTitle,
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => PageBody(
          children: [PageIntroCard(text: l10n.ruleVersionsUnavailable)],
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return PageBody(
              children: [
                PageIntroCard(text: l10n.ruleVersionsIntro),
                generateSection(
                  items: [
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.info),
                      title: Text(l10n.ruleVersionsNone),
                    ),
                  ],
                ),
              ],
            );
          }
          final selectedId = _resolveSelection(entries);
          final entry = entries.firstWhere((e) => e.id == selectedId);
          final history = _VersionHistory(
            subscriptionId: entry.id,
            onCompare: _compare,
            onRollback: (version) => _rollback(entry, version),
            busy: _busy,
          );
          // U9: on a tablet, keep the subscription list beside the history instead of hiding it in a
          // dropdown, so switching versions never costs a second tap through a menu.
          final wide = MediaQuery.sizeOf(context).width >= 720;
          if (wide) {
            return PageBody(
              children: [
                PageIntroCard(text: l10n.ruleVersionsIntro),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 320,
                      child: _SubscriptionPicker(
                        entries: entries,
                        selectedId: selectedId,
                        onSelect: (id) => setState(() => _selectedId = id),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: history),
                  ],
                ),
              ],
            );
          }
          return PageBody(
            children: [
              PageIntroCard(text: l10n.ruleVersionsIntro),
              generateSection(
                items: [
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.link),
                    title: Text(l10n.ruleVersionsPick),
                    trailing: PopupSelectButton<int>(
                      value: selectedId,
                      semanticLabel: l10n.ruleVersionsPick,
                      items: [for (final e in entries) (e.id, e.name)],
                      onChanged: (value) => setState(() => _selectedId = value),
                    ),
                  ),
                ],
              ),
              history,
            ],
          );
        },
      ),
    );
  }

  int _resolveSelection(List<SubscriptionEntry> entries) {
    final current = _selectedId;
    if (current != null && entries.any((e) => e.id == current)) {
      return current;
    }
    return entries.first.id;
  }

  Future<void> _compare(
    StoredRuleVersion current,
    StoredRuleVersion other,
  ) async {
    final l10n = context.l10n;
    final diff = RustRuleVersionCore.instance.diff(other.rules, current.rules);
    if (!mounted) return;
    await showFloatingDialog<void>(
      context: context,
      child: CommonDialog(
        title: l10n.ruleVersionsDiffTitle,
        actions: [
          TextButton(
            onPressed: () => popFloatingDialog(context),
            child: Text(l10n.uiClose),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.ruleVersionsDiffSummary(diff.addedCount, diff.removedCount),
            ),
            if (diff.added.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.ruleVersionsAdded,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              Text(diff.added.take(50).join('\n')),
            ],
            if (diff.removed.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.ruleVersionsRemoved,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              Text(diff.removed.take(50).join('\n')),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _rollback(
    SubscriptionEntry entry,
    StoredRuleVersion version,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: l10n.ruleVersionsRollback,
        actions: [
          TextButton(
            onPressed: () => popFloatingDialog(context, false),
            child: Text(l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => popFloatingDialog(context, true),
            child: Text(l10n.ruleVersionsRollback),
          ),
        ],
        child: Text(l10n.ruleVersionsRollbackConfirm),
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final importer = await ref.read(ruleImporterProvider.future);
      if (importer == null) {
        throw StateError(l10n.ruleVersionsUnavailable);
      }
      final source = subscriptionSourceTag(entry.id);
      final parsed = parseCategorized(version.rules.join('\n'));
      await importer.removeRulesBySource(source);
      await importer.import(
        parsed,
        source: source,
        kind: entry.kind.storageValue,
        enabled: entry.enabled,
      );
      final repository = await ref.read(ruleVersionRepositoryProvider.future);
      await repository?.recordVersion(
        groupId: source,
        hash: version.hash,
        ruleCount: version.ruleCount,
        rules: version.rules,
      );
      ref.read(subscriptionRevisionProvider.notifier).bump();
      _snack(l10n.ruleVersionsRollbackDone);
    } catch (error) {
      _snack(l10n.ruleVersionsRollbackFailed('$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SubscriptionPicker extends StatelessWidget {
  const _SubscriptionPicker({
    required this.entries,
    required this.selectedId,
    required this.onSelect,
  });

  final List<SubscriptionEntry> entries;
  final int selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return generateSection(
      title: l10n.ruleVersionsPick,
      items: [
        for (final entry in entries)
          ListItem(
            leading: const GlyphIcon(AppGlyphs.link),
            title: Text(entry.name),
            trailing: entry.id == selectedId ? const SelectionCheck() : null,
            onTap: () => onSelect(entry.id),
          ),
      ],
    );
  }
}

class _VersionHistory extends ConsumerWidget {
  const _VersionHistory({
    required this.subscriptionId,
    required this.onCompare,
    required this.onRollback,
    required this.busy,
  });

  final int subscriptionId;
  final void Function(StoredRuleVersion current, StoredRuleVersion other)
  onCompare;
  final void Function(StoredRuleVersion version) onRollback;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repositoryAsync = ref.watch(ruleVersionRepositoryProvider);
    return repositoryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => generateSection(
        items: [
          ListItem(
            leading: const GlyphIcon(AppGlyphs.info),
            title: Text(l10n.ruleVersionsUnavailable),
          ),
        ],
      ),
      data: (repository) {
        if (repository == null) {
          return generateSection(
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.info),
                title: Text(l10n.ruleVersionsUnavailable),
              ),
            ],
          );
        }
        return FutureBuilder<List<StoredRuleVersion>>(
          future: repository.history('sub_$subscriptionId', limit: 10),
          builder: (context, snapshot) {
            final history = snapshot.data;
            if (history == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (history.isEmpty) {
              return generateSection(
                items: [
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.info),
                    title: Text(l10n.ruleVersionsEmpty),
                  ),
                ],
              );
            }
            final current = history.first;
            return generateSection(
              items: [
                for (var i = 0; i < history.length; i++)
                  _versionItem(context, l10n, history[i], i == 0, current),
              ],
            );
          },
        );
      },
    );
  }

  Widget _versionItem(
    BuildContext context,
    AppL10n l10n,
    StoredRuleVersion version,
    bool isCurrent,
    StoredRuleVersion current,
  ) {
    final title =
        '${version.hash} · ${l10n.ruleVersionsRuleCount(version.ruleCount)}';
    return ListItem(
      leading: GlyphIcon(
        isCurrent ? AppGlyphs.checkCircle : AppGlyphs.clock,
        size: 20,
      ),
      title: Text(title),
      subtitle: Text(_formatTime(version.createdAt)),
      trailing: isCurrent
          ? Text(l10n.ruleVersionsCurrent)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: busy ? null : () => onCompare(current, version),
                  child: Text(l10n.ruleVersionsCompare),
                ),
                TextButton(
                  onPressed: busy ? null : () => onRollback(version),
                  child: Text(l10n.ruleVersionsRollback),
                ),
              ],
            ),
    );
  }

  static String _formatTime(int epochMs) {
    final time = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
