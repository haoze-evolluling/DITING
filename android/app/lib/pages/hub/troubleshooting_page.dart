library;

import 'dart:async';

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/native/db_health_bridge.dart';
import 'package:diting_android/data/native/runtime_event.dart';
import 'package:diting_android/data/native/runtime_log_bridge.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/db_health_providers.dart';
import 'package:diting_android/state/runtime_event_providers.dart';
import 'package:diting_android/state/runtime_log_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
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
  bool _busy = false;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshRuntimeStatus();
      _refreshDbHealth();
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
    if (state == AppLifecycleState.resumed) {
      _refreshRuntimeStatus(force: true);
      _refreshDbHealth();
    }
  }

  Future<void> _refreshDbHealth() async {
    await ref.read(dbWriteHealthProvider.notifier).refresh();
  }

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
      (_) => _refreshRuntimeStatus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(runtimeLogStatusProvider).value;
    final capturing = status?.capturing ?? false;
    final dbHealth = ref.watch(dbWriteHealthProvider).value;
    final events =
        ref.watch(runtimeEventsProvider).value ?? const <RuntimeEvent>[];
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
                leading: const Icon(TablerIcons.logs, size: 20),
                title: Text(context.l10n.troubleshootLogsViewLogs),
                subtitle: Text(context.l10n.troubleshootLogsViewLogsBody),
                trailing: const Icon(TablerIcons.chevron_right, size: 18),
                onTap: () => context.push(HubPaths.troubleshootingLogs),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.troubleshootRuntimeLogs,
            items: [
              ListItem.toggle(
                leading: Icon(
                  capturing ? TablerIcons.circle_check : TablerIcons.player_record,
                  size: 20,
                ),
                title: Text(context.l10n.troubleshootRecordLogs),
                subtitle: Text(_switchSubtitle(status)),
                value: capturing,
                onChanged: _busy ? null : (value) => _onToggle(value),
              ),
              ListItem.toggle(
                leading: const Icon(TablerIcons.adjustments, size: 20),
                title: Text(context.l10n.troubleshootDetailMode),
                subtitle: Text(context.l10n.troubleshootDetailModeNote),
                value: detailed,
                onChanged: _busy ? null : _onModeToggle,
              ),
            ],
            footer: context.l10n.troubleshootRecordNote,
          ),
          generateSection(
            title: context.l10n.troubleshootEventsTitle,
            items: [
              ListItem(
                leading: Icon(
                  eventSummary.hasAnomaly ? TablerIcons.alert_triangle : TablerIcons.clock,
                  size: 20,
                  color: eventSummary.hasAnomaly ? error : null,
                ),
                title: Text(context.l10n.troubleshootEventsOpen),
                subtitle: Text(_eventsSubtitle(eventSummary)),
                trailing: const Icon(TablerIcons.chevron_right, size: 18),
                onTap: () => context.push(HubPaths.troubleshootingEvents),
              ),
            ],
            footer: context.l10n.troubleshootEventsRecentBody,
          ),
          generateSection(
            title: context.l10n.troubleshootLocalDb,
            items: [
              ListItem(
                leading: Icon(
                  (dbHealth?.healthy ?? true)
                      ? TablerIcons.circle_check
                      : TablerIcons.alert_triangle,
                  color: (dbHealth?.healthy ?? true) ? null : error,
                  size: 20,
                ),
                title: Text(context.l10n.troubleshootWriteStatus),
                subtitle: Text(_dbHealthSubtitle(dbHealth)),
                onTap: _refreshDbHealth,
              ),
            ],
            footer: context.l10n.troubleshootWriteStatusNote,
          ),
          ListFooter(text: context.l10n.troubleshootCaptureWarning),
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

  String _dbHealthSubtitle(DbWriteHealthSnapshot? health) {
    if (health == null) return context.l10n.troubleshootReadingHealth;
    if (health.healthy) {
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
    return context.l10n.troubleshootDropped(dropped, split, failed, reason);
  }

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

  Future<void> _onToggle(bool value) async {
    if (!value) {
      setState(() => _busy = true);
      await ref.read(runtimeLogStatusProvider.notifier).stop();
      if (!mounted) return;
      setState(() => _busy = false);
      _syncPolling(false);
      showAppSnack(context, context.l10n.troubleshootStoppedToast);
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
        child: Text(context.l10n.troubleshootStartBody),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final started = await ref.read(runtimeLogStatusProvider.notifier).start();
    if (!mounted) return;
    setState(() => _busy = false);
    _syncPolling(started);
    showAppSnack(
      context,
      started
          ? context.l10n.troubleshootStartedToast
          : context.l10n.troubleshootStartFailedToast,
    );
  }

  String _eventsSubtitle(RuntimeEventSummary summary) {
    if (summary.count == 0) return context.l10n.troubleshootEventsEmpty;
    if (summary.hasAnomaly) {
      return context.l10n.troubleshootEventsAnomaly(summary.anomalyCount);
    }
    return context.l10n.troubleshootEventsCount(summary.count);
  }

  Future<void> _onModeToggle(bool detailed) async {
    setState(() => _busy = true);
    await ref.read(runtimeLogStatusProvider.notifier).setMode(detailed);
    if (!mounted) return;
    setState(() => _busy = false);
  }
}
