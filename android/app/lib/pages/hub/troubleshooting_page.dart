/// 故障排查: one page for everything a user would send a developer — the crash reports written
/// automatically, plus the manual runtime-logcat capture. Both are troubleshooting material, so
/// they share a surface instead of two nearly identical cards in 数据与维护.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';

import 'package:diting_android/data/native/db_health_bridge.dart';
import 'package:diting_android/data/native/runtime_event.dart';
import 'package:diting_android/data/native/runtime_log_bridge.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/db_health_providers.dart';
import 'package:diting_android/state/runtime_event_providers.dart';
import 'package:diting_android/state/runtime_log_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class TroubleshootingPage extends ConsumerStatefulWidget {
  const TroubleshootingPage({super.key});

  @override
  ConsumerState<TroubleshootingPage> createState() =>
      _TroubleshootingPageState();
}

class _TroubleshootingPageState extends ConsumerState<TroubleshootingPage>
    with WidgetsBindingObserver {
  /// Blocks a second tap while the start/stop round trip runs, so two services cannot race.
  bool _busy = false;

  /// Ticks while capture is on so the file count and size stay live; the state provider is not
  /// auto-disposed, so nothing else would re-read the disk.
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The provider outlives the page, so a reopen would otherwise show the size from last time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshRuntimeStatus();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshDbHealth();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Both sources change outside the page — crashes are collected by the app, and the capture
    // keeps running behind the notification — so re-read on resume.
    if (state == AppLifecycleState.resumed) {
      _refreshRuntimeStatus(force: true);
      _refreshDbHealth();
    }
  }

  /// Log-write counters change while the tunnel runs, so every open and resume re-reads them.
  Future<void> _refreshDbHealth() async {
    await ref.read(dbWriteHealthProvider.notifier).refresh();
  }

  /// Re-reads the native capture status and keeps the live size ticking only while it is on.
  Future<void> _refreshRuntimeStatus({bool force = false}) async {
    if (_busy && !force) return;
    final status = await ref.read(runtimeLogStatusProvider.notifier).refresh();
    if (!mounted) return;
    _syncPolling(status.capturing);
  }

  void _syncPolling(bool capturing) {
    if (!capturing) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(
      const Duration(seconds: 2),
      // Through [_refreshRuntimeStatus] so a capture stopped from the notification also stops it.
      (_) => _refreshRuntimeStatus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(runtimeLogStatusProvider).value;
    final capturing = status?.capturing ?? false;
    final dbHealth = ref.watch(dbWriteHealthProvider).value;
    final events = ref.watch(runtimeEventsProvider).value ?? const <RuntimeEvent>[];
    final eventSummary = RuntimeEventSummary(events);
    final detailed = status?.detailed ?? false;
    final error = context.colorScheme.error;
    return CommonScaffold(
      title: context.l10n.troubleshootTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.troubleshootLogsTitle,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.logs, size: 20),
                title: Text(context.l10n.troubleshootLogsViewLogs),
                subtitle: Text(context.l10n.troubleshootLogsViewLogsBody),
                trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                onTap: () => context.push(HubPaths.troubleshootingLogs),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.troubleshootRuntimeLogs,
            items: [
              ListItem.toggle(
                leading: GlyphIcon(
                  capturing ? AppGlyphs.checkCircle : AppGlyphs.logs,
                  size: 20,
                ),
                title: Text(context.l10n.troubleshootRecordLogs),
                subtitle: Text(_switchSubtitle(status)),
                value: capturing,
                onChanged: _busy ? null : (value) => _onToggle(value),
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.logs, size: 20),
                title: Text(context.l10n.troubleshootDetailMode),
                subtitle: Text(context.l10n.troubleshootDetailModeNote),
                value: detailed,
                onChanged: _busy ? null : _onModeToggle,
              ),
            ],
            footer:
                context.l10n.troubleshootRecordNote,
          ),
          generateSection(
            title: context.l10n.troubleshootEventsTitle,
            items: [
              ListItem(
                leading: GlyphIcon(
                  eventSummary.hasAnomaly ? AppGlyphs.warning : AppGlyphs.logs,
                  size: 20,
                  color: eventSummary.hasAnomaly ? error : null,
                ),
                title: Text(context.l10n.troubleshootEventsOpen),
                subtitle: Text(_eventsSubtitle(eventSummary)),
                trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                onTap: () => context.push(HubPaths.troubleshootingEvents),
              ),
            ],
            footer: context.l10n.troubleshootEventsRecentBody,
          ),
          generateSection(
            title: context.l10n.troubleshootLocalDb,
            items: [
              ListItem(
                leading: GlyphIcon(
                  (dbHealth?.healthy ?? true)
                      ? AppGlyphs.checkCircle
                      : AppGlyphs.warning,
                  color: (dbHealth?.healthy ?? true) ? null : error,
                  size: 20,
                ),
                title: Text(context.l10n.troubleshootWriteStatus),
                subtitle: Text(_dbHealthSubtitle(dbHealth)),
                onTap: _refreshDbHealth,
              ),
            ],
            footer:
                context.l10n.troubleshootWriteStatusNote,
          ),
          ListFooter(
            text:
                context.l10n.troubleshootCaptureWarning,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _switchSubtitle(RuntimeLogStatus? status) {
    if (status == null) return context.l10n.troubleshootReadingStatus;
    if (status.capturing) {
      return context.l10n.troubleshootRecording(status.sizeLabel);
    }
    return status.hasLogs
        ? context.l10n.troubleshootStoppedWithLogs(status.sizeLabel)
        : context.l10n.troubleshootStoppedNoLogs;
  }

  /// The subtitle reflects the real count; an unreadable count says so instead of inventing one.
  String _dbHealthSubtitle(DbWriteHealthSnapshot? health) {
    if (health == null) return context.l10n.troubleshootReadingHealth;
    if (health.healthy) {
      // The probe is what makes this trustworthy: "0 dropped" also happens when nothing writes.
      if (!health.probeOk) return context.l10n.troubleshootHealthy;
      return context.l10n.troubleshootHealthyDetail(
        health.probeJournalMode,
        'busy ${health.probeBusyTimeoutMs}ms',
      );
    }
    final dropped = health.droppedRows;
    final failed = health.openFailures;
    final cause = health.lastCause.isEmpty
        ? health.probeCause
        : health.lastCause;
    final reason = cause.isEmpty ? '' : '（$cause）';
    final split = _dropBreakdown(health.droppedByReason, context.l10n);
    return context.l10n.troubleshootDropped(
      dropped,
      split,
      failed,
      reason,
    );
  }

  /// "（队列溢出 120 · 表缺失 3）": tells a busy database from a missing table at a glance.
  static String _dropBreakdown(Map<String, int> byReason, AppL10n l10n) {
    final labels = {
      'overflow': l10n.troubleshootOverflow,
      'tableMissing': l10n.troubleshootTableMissing,
      'noDatabase': l10n.troubleshootNoDatabase,
      'closed': l10n.troubleshootClosed,
    };
    final parts = [
      for (final entry in labels.entries)
        if ((byReason[entry.key] ?? 0) > 0)
          '${entry.value} ${byReason[entry.key]}',
    ];
    return parts.isEmpty ? '' : '（${parts.join(' · ')}）';
  }

  /// Turning on is the risky direction, so it asks first; turning off just stops.
  Future<void> _onToggle(bool value) async {
    if (!value) {
      setState(() => _busy = true);
      await ref.read(runtimeLogStatusProvider.notifier).stop();
      if (!mounted) return;
      setState(() => _busy = false);
      _syncPolling(false);
      _toast(context.l10n.troubleshootStoppedToast);
      return;
    }
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.troubleshootStartTitle,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.troubleshootCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.troubleshootConfirmStart),
          ),
        ],
        child: Text(
          context.l10n.troubleshootStartBody,
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final started = await ref.read(runtimeLogStatusProvider.notifier).start();
    if (!mounted) return;
    setState(() => _busy = false);
    _syncPolling(started);
    _toast(started ? context.l10n.troubleshootStartedToast : context.l10n.troubleshootStartFailedToast);
  }

  /// The recent-events row: empty, an anomaly count, or the plain total.
  String _eventsSubtitle(RuntimeEventSummary summary) {
    if (summary.count == 0) return context.l10n.troubleshootEventsEmpty;
    if (summary.hasAnomaly) {
      return context.l10n.troubleshootEventsAnomaly(summary.anomalyCount);
    }
    return context.l10n.troubleshootEventsCount(summary.count);
  }

  /// Switches the capture tier; the native side persists it and re-arms a running capture.
  Future<void> _onModeToggle(bool detailed) async {
    setState(() => _busy = true);
    await ref.read(runtimeLogStatusProvider.notifier).setMode(detailed);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
