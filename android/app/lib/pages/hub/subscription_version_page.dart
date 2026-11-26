library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/db/rule_dataset_providers.dart';
import 'package:diting_android/data/db/rule_version_repository.dart';
import 'package:diting_android/data/rules/rule_importer.dart';
import 'package:diting_android/data/rules/rule_parser.dart';
import 'package:diting_android/data/rules/rust_rule_version_core.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
          children: [_ErrorNotice(text: l10n.ruleVersionsUnavailable)],
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const PageBody(children: []);
          }
          final selectedId = _resolveSelection(entries);
          final entry = entries.firstWhere((e) => e.id == selectedId);
          final history = _VersionHistory(
            subscriptionId: entry.id,
            onCompare: _compare,
            onRollback: (version) => _rollback(entry, version),
            busy: _busy,
          );
          final wide = MediaQuery.sizeOf(context).width >= 720;
          if (wide) {
            return PageBody(
              children: [
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
              generateSection(
                title: l10n.ruleVersionsPick,
                items: [
                  ListItem(
                    leading: const Icon(TablerIcons.link),
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
              const ListSectionGap(),
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
                style: AppTextRole.supportingText
                    .of(context)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              Text(diff.added.take(50).join('\n')),
            ],
            if (diff.removed.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.ruleVersionsRemoved,
                style: AppTextRole.supportingText
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
      final staging = subscriptionStagingTag(entry.id);
      // 与更新流程一致：流式分片导入暂存来源，再原子切换。
      final stream = streamParseCategorized(version.rules.join('\n'));
      await importer.removeRulesBySource(staging);
      try {
        for (var chunk = stream.next(); chunk != null; chunk = stream.next()) {
          if (chunk.isEmpty) continue;
          await importer.import(
            chunk,
            source: staging,
            kind: entry.kind.storageValue,
            enabled: entry.enabled,
          );
        }
        await importer.commitStaging(staging, source, enabled: entry.enabled);
      } catch (_) {
        try {
          await importer.removeRulesBySource(staging);
        } catch (_) {}
        rethrow;
      } finally {
        stream.dispose();
      }
      final repository = await ref.read(ruleVersionRepositoryProvider.future);
      await repository?.recordVersion(
        groupId: source,
        hash: version.hash,
        ruleCount: version.ruleCount,
        rules: version.rules,
      );
      // 回滚后订阅内容已不同于服务器缓存版本；同步哈希并清掉校验器，
      // 否则下次更新会因哈希相同而跳过导入。
      final subscriptions = await ref.read(
        subscriptionRepositoryProvider.future,
      );
      await subscriptions?.markImported(
        entry.id,
        ruleCount: version.ruleCount,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
        etag: null,
        lastModified: null,
        ruleSetHash: version.hash,
      );
      scheduleRuleIndexRefresh(ref.read(activeDataSetProvider).ruleIndex);
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

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InlineNotice(
        message: text,
        glyph: TablerIcons.alert_circle,
        color: colorScheme.errorContainer,
        foregroundColor: colorScheme.onErrorContainer,
      ),
    );
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
            leading: const Icon(TablerIcons.link),
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
      error: (error, _) => _ErrorNotice(text: l10n.ruleVersionsUnavailable),
      data: (repository) {
        if (repository == null) {
          return _ErrorNotice(text: l10n.ruleVersionsUnavailable);
        }
        return FutureBuilder<List<StoredRuleVersion>>(
          future: repository.history('sub_$subscriptionId', limit: 10),
          builder: (context, snapshot) {
            final history = snapshot.data;
            if (history == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (history.isEmpty) {
              return const SizedBox.shrink();
            }
            final current = history.first;
            return generateSection(
              title: l10n.ruleVersionsHistory,
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
      leading: Icon(
        isCurrent ? TablerIcons.circle_check : TablerIcons.clock,
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
