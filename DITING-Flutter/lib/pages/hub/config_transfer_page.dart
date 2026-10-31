// ignore_for_file: sort_child_properties_last
import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/backup/backup_importer.dart';
import 'package:diting/data/backup/backup_models.dart';
import 'package:diting/routes/hub_routes.dart';
import 'package:diting/state/backup_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/nav_entry_row.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Backup and migration (upstream `ConfigTransferScreen`): export writes through the system
/// document
/// picker, import reads and merges the chosen file. Both share the [BackupGroup] checklist.
class ConfigTransferPage extends ConsumerStatefulWidget {
  const ConfigTransferPage({super.key});

  @override
  ConsumerState<ConfigTransferPage> createState() => _ConfigTransferPageState();
}

class _ConfigTransferPageState extends ConsumerState<ConfigTransferPage> {
  final Set<BackupGroup> _selected = {...BackupGroup.values};

  /// The running action; while non-null both entries are disabled so no second picker opens.
  String? _busy;

  bool get _allSelected => _selected.length == BackupGroup.values.length;
  bool get _noneSelected => _selected.isEmpty;

  void _toggleAll() {
    final selectAll = !_allSelected;
    setState(() {
      _selected.clear();
      if (selectAll) _selected.addAll(BackupGroup.values);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(backupStatsProvider).value;
    return CommonScaffold(
      title: context.l10n.transferTitle,
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _metric(context, context.l10n.transferMetricProviders, _figure(stats?.providers)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric(
                    context,
                    context.l10n.transferMetricSubs,
                    _figure(stats?.subscriptions),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _metric(context, context.l10n.transferMetricCustomRules, _figure(stats?.customRules)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric(context, context.l10n.transferMetricListedApps, _figure(stats?.listedApps)),
                ),
              ],
            ),
          ),
          for (final group in _sections(context.l10n))
            generateSection(
              title: group.title,
              actions: group.selectable
                  ? [
                      IconButtonData(
                        glyph: _allSelected
                            ? AppGlyphs.deselect
                            : AppGlyphs.selectAll,
                        tooltip: _allSelected ? context.l10n.transferDeselectAll : context.l10n.commonSelectAll,
                        onPressed: _toggleAll,
                      ),
                    ]
                  : const [],
              items: [
                for (final item in group.groups)
                  ListItem(
                    leading: GlyphIcon(
                      _selected.contains(item)
                          ? AppGlyphs.checkCircle
                          : AppGlyphs.rules,
                      size: 20,
                    ),
                    title: Text(item.title(context.l10n)),
                    subtitle: Text(item.description(context.l10n)),
                    trailing: _selected.contains(item)
                        ? const SelectionCheck()
                        : null,
                    onTap: () => setState(() {
                      if (!_selected.remove(item)) _selected.add(item);
                    }),
                  ),
              ],
            ),
          generateSection(
            title: context.l10n.transferImportExportSection,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.export),
                title: Text(context.l10n.transferExportJson),
                subtitle: Text(
                  _noneSelected
                      ? context.l10n.transferExportHintNone
                      : context.l10n.transferExportHintCount(_selected.length),
                ),
                onTap: _noneSelected || _busy != null ? null : _export,
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.importFile),
                title: Text(context.l10n.transferImportJson),
                subtitle: Text(context.l10n.transferImportSubtitle),
                onTap: _busy != null ? null : _import,
              ),
            ],
            footer: context.l10n.transferImportExportFooter,
          ),
          generateSection(
            title: context.l10n.transferCloudSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.cloudSync,
                title: context.l10n.transferWebdav,
                subtitle: context.l10n.transferWebdavSubtitle,
                onPressed: () => context.push(HubPaths.configTransferWebdav),
              ),
            ],
          ),
          if (_busy != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                spacing: 8,
                children: [
                  const CommonCircleLoading(size: 16),
                  Expanded(
                    child: Text(_busy!, style: context.listCaptionStyle),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<({String title, List<BackupGroup> groups, bool selectable})> _sections(
    AppL10n l10n,
  ) => [
    (
      title: l10n.transferSectionAppConfig,
      selectable: true,
      groups: const [
        BackupGroup.providers,
        BackupGroup.bootstrap,
        BackupGroup.cache,
        BackupGroup.outbound,
      ],
    ),
    (
      title: l10n.transferSectionRules,
      selectable: false,
      groups: const [
        BackupGroup.subscriptions,
        BackupGroup.domainRules,
        BackupGroup.rewriteDomain,
        BackupGroup.rewriteCname,
        BackupGroup.addressRules,
      ],
    ),
    (
      title: l10n.transferSectionAppControl,
      selectable: false,
      groups: const [
        BackupGroup.excluded,
        BackupGroup.blocked,
        BackupGroup.allowlist,
        BackupGroup.httpInspection,
      ],
    ),
    (
      title: l10n.transferSectionPersonal,
      selectable: false,
      groups: const [BackupGroup.appearance, BackupGroup.system],
    ),
  ];

  /// A dash while the counts load; showing 0 would read as "no rules on this device".
  String _figure(int? value) => value == null ? '—' : '$value';

  Widget _metric(BuildContext context, String label, String value) =>
      CommonCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Text(value, style: context.listTitleStyle),
            Text(label, style: context.listCaptionStyle),
          ],
        ),
      );

  Future<void> _export() async {
    setState(() => _busy = context.l10n.transferBusyExporting);
    try {
      final outcome = await ref.read(backupActionsProvider).exportToDocument(_selected);
      if (!mounted) return;
      if (outcome.cancelled) {
        _toast(context.l10n.transferExportCancelled);
        return;
      }
      if (outcome.error != null) {
        _toast(outcome.error!);
        return;
      }
      final export = outcome.result;
      if (export == null) {
        _toast(context.l10n.transferExportEmpty);
        return;
      }
      _toast(
        '${context.l10n.transferExportDone(export.included.length, export.totalItems)}'
        '${export.skipped.isEmpty ? '' : context.l10n.transferExportSkipped(export.skipped.length)}',
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = context.l10n.transferBusyPickingImport);
    final BackupImportResult result;
    try {
      result = await ref.read(backupActionsProvider).importFromDocument();
    } finally {
      // Clear the progress before the dialog opens, otherwise "waiting for the backup file"
      // stays behind it and looks like the import is still running.
      if (mounted) setState(() => _busy = null);
    }
    if (!mounted) return;
    if (result.cancelled) {
      _toast(context.l10n.transferImportCancelled);
      return;
    }
    await showFloatingDialog<void>(
      context: context,
      child: _ImportResultDialog(result: result),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

/// Reports only what happened: added, updated and skipped counts per group.
class _ImportResultDialog extends StatelessWidget {
  const _ImportResultDialog({required this.result});

  final BackupImportResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonDialog(
      title: context.l10n.transferImportTitle,
      trailing: MetaChip(label: result.failed ? context.l10n.transferImportFailedChip : context.l10n.transferImportDoneChip),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          if (result.failed) ...[
            Text(
              result.fatalError!,
              style: TextStyle(color: colorScheme.error),
            ),
          ] else ...[
            Text(
              context.l10n.transferImportSummary(
                result.added,
                result.updated,
                result.skipped,
              ),
              style: context.listTitleStyle,
            ),
            if (result.sourceName != null)
              Text(
                context.l10n.transferSourceFile(result.sourceName!),
                style: context.listCaptionStyle,
              ),
            if (result.occurredAt != null)
              Text(
                context.l10n.transferExportedAt(_dateText(result.occurredAt!)),
                style: context.listCaptionStyle,
              ),
            for (final outcome in result.changed)
              Text(
                context.l10n.transferOutcomeRow(
                  outcome.group.title(context.l10n),
                  _outcomeText(context.l10n, outcome),
                ),
              ),
            for (final outcome in result.failedGroups)
              Text(
                context.l10n.transferFailedGroupRow(
                  outcome.group.title(context.l10n),
                  outcome.error ?? '',
                ),
                style: TextStyle(color: colorScheme.error),
              ),
            if (result.changed.isEmpty && result.failedGroups.isEmpty)
              Text(context.l10n.transferNothingChanged),
            if (result.subscriptionCount > 0)
              Text(
                context.l10n.transferSubscriptionsNote(result.subscriptionCount),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.transferDone),
        ),
      ],
    );
  }

  String _outcomeText(AppL10n l10n, BackupGroupOutcome outcome) {
    final parts = <String>[];
    if (outcome.added > 0) parts.add(l10n.transferOutcomeAdded(outcome.added));
    if (outcome.updated > 0) {
      parts.add(l10n.transferOutcomeUpdated(outcome.updated));
    }
    if (outcome.skipped > 0) {
      parts.add(l10n.transferOutcomeSkipped(outcome.skipped));
    }
    return parts.isEmpty
        ? l10n.transferNoChange
        : parts.join(l10n.transferOutcomeSeparator);
  }

  static String _dateText(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
