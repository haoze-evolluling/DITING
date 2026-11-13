/// 日志管理: one merged, newest-first timeline of runtime captures and crash reports. Per-file
/// rows open a viewer that can share or delete that file; the app bar also shares or clears
/// everything. The heavy lifting (listing, reading, deleting, sharing) stays in
/// [TroubleshootingLogBridge] on the native side.
library;

import 'package:diting_android/data/native/troubleshooting_log_bridge.dart';
import 'package:diting_android/pages/hub/troubleshooting_log_detail_sheet.dart';
import 'package:diting_android/state/troubleshooting_log_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class TroubleshootingLogsPage extends ConsumerStatefulWidget {
  const TroubleshootingLogsPage({super.key});

  @override
  ConsumerState<TroubleshootingLogsPage> createState() =>
      _TroubleshootingLogsPageState();
}

class _TroubleshootingLogsPageState
    extends ConsumerState<TroubleshootingLogsPage>
    with WidgetsBindingObserver {
  /// Blocks a second tap while a delete or share round trip runs.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A capture may have started or a crash landed while this page was away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() =>
      ref.read(troubleshootingLogsProvider.notifier).refresh();

  Future<void> _shareAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    final shared = await ref.read(troubleshootingLogBridgeProvider).shareAll();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(
      shared
          ? context.l10n.troubleshootLogsShared
          : context.l10n.troubleshootLogsShareFailed,
    );
  }

  Future<void> _clearAll() async {
    if (_busy) return;
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.troubleshootLogsClearAllTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.troubleshootLogsClearAllBody),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await ref.read(troubleshootingLogBridgeProvider).clearAll();
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(
      result.total > 0
          ? context.l10n.troubleshootLogsClearedAll(
              result.runtime,
              result.crash,
            )
          : context.l10n.troubleshootLogsEmpty,
    );
  }

  /// Opens the viewer; a deleted or shared file refreshes the timeline and confirms with a toast.
  Future<void> _open(TroubleshootLogEntry entry) async {
    final action = await showSheet<String>(
      context: context,
      builder: (_) => TroubleshootingLogDetailSheet(entry: entry),
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    if (action == 'deleted') _toast(context.l10n.troubleshootLogsDeleted);
    if (action == 'shared') _toast(context.l10n.troubleshootLogsShared);
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _kindLabel(TroubleshootLogKind kind) =>
      kind == TroubleshootLogKind.runtime
      ? context.l10n.troubleshootLogKindRuntime
      : context.l10n.troubleshootLogKindCrash;

  Widget _row(TroubleshootLogEntry entry) {
    final colorScheme = context.colorScheme;
    return ListItem(
      leading: GlyphIcon(
        entry.isRuntime ? AppGlyphs.logs : AppGlyphs.wrench,
        size: 20,
        color: entry.isRuntime ? null : colorScheme.warning,
      ),
      title: Text(entry.timeLabel),
      subtitle: Text('${_kindLabel(entry.kind)} · ${entry.sizeLabel}'),
      trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
      onTap: _busy ? null : () => _open(entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncLogs = ref.watch(troubleshootingLogsProvider);
    final entries = asyncLogs.value ?? const <TroubleshootLogEntry>[];
    final hasEntries = entries.isNotEmpty;
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.troubleshootLogsTitle,
      menuItems: [
        CommonPopupMenuItem(
          label: l10n.troubleshootLogsRefresh,
          glyph: AppGlyphs.refresh,
          onPressed: _refresh,
        ),
        CommonPopupMenuItem(
          label: l10n.troubleshootLogsShareAll,
          glyph: AppGlyphs.send,
          onPressed: hasEntries && !_busy ? _shareAll : null,
        ),
        CommonPopupMenuItem(
          label: l10n.troubleshootLogsClearAll,
          glyph: AppGlyphs.delete,
          danger: true,
          onPressed: hasEntries && !_busy ? _clearAll : null,
        ),
      ],
      body: NullStatusSwitcher(
        isLoading: asyncLogs.isLoading && !asyncLogs.hasValue,
        isEmpty: entries.isEmpty,
        loadingStatus: NullStatus(
          label: l10n.troubleshootLogsReading,
          illustration: NullStatusIllustration.logs,
        ),
        nullStatus: NullStatus(
          label: l10n.troubleshootLogsEmpty,
          description: l10n.troubleshootLogsEmptyBody,
          illustration: NullStatusIllustration.logs,
        ),
        child: PageBody(
          children: [
            generateSection(
              title: l10n.troubleshootLogsAll,
              items: [for (final entry in entries) _row(entry)],
              footer: l10n.troubleshootLogsCount(entries.length),
            ),
            ListFooter(text: l10n.troubleshootLogsFooter),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
