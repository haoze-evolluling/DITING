import 'dart:async';

import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'server_logs_widgets.dart';

class ServerLogsPage extends ConsumerStatefulWidget {
  const ServerLogsPage({super.key});

  @override
  ConsumerState<ServerLogsPage> createState() => _ServerLogsPageState();
}

class _ServerLogsPageState extends ConsumerState<ServerLogsPage>
    with PageVisibilityMixin<ServerLogsPage> {
  static const _pageSize = 50;
  static const _searchDelay = Duration(milliseconds: 300);

  final _domain = TextEditingController();
  Timer? _pollTimer;
  Timer? _searchTimer;
  String _domainQuery = '';
  String _client = '';
  String _status = '';
  String _qtype = '';
  String _range = 'all';
  int _rangeStartMs = 0;
  int _page = 0;

  ServerLogQuery get _query => ServerLogQuery(
    domain: _domainQuery,
    client: _client,
    status: _status,
    qtype: _qtype,
    startMs: _rangeStartMs,
    limit: _pageSize,
    offset: _page * _pageSize,
  );

  void _setRange(String range) {
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _range = range;
      _rangeStartMs = switch (range) {
        '24h' => now - const Duration(hours: 24).inMilliseconds,
        '7d' => now - const Duration(days: 7).inMilliseconds,
        _ => 0,
      };
      _page = 0;
    });
  }

  Future<void> _openTypeFilter() async {
    const types = ['', 'A', 'AAAA', 'CNAME', 'HTTPS', 'TXT', 'MX', 'NS'];
    final selected = await showSheet<String>(
      context: context,
      builder: (_) => _TypeFilterSheet(selected: _qtype, types: types),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _qtype = selected;
      _page = 0;
    });
  }

  @override
  void onPageVisibilityChanged(bool visible) {
    _pollTimer?.cancel();
    _pollTimer = visible
        ? Timer.periodic(const Duration(seconds: 5), (_) {
            if (ref.read(serverControllerProvider).value?.status.running ==
                true) {
              ref.read(serverControllerProvider.notifier).refreshLive();
            }
          })
        : null;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchTimer?.cancel();
    _domain.dispose();
    super.dispose();
  }

  void _onDomainChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDelay, () => _applyDomain(value));
  }

  void _applyDomain(String value) {
    _searchTimer?.cancel();
    if (!mounted) return;
    final next = value.trim();
    if (next == _domainQuery) return;
    setState(() {
      _domainQuery = next;
      _page = 0;
    });
  }

  Future<void> _openClientFilter(
    ServerStats stats,
    ServerQueryResult? result,
  ) async {
    final clients = <String>{
      if (_client.isNotEmpty) _client,
      for (final item in stats.topClients)
        if (item.name.isNotEmpty) item.name,
      for (final item in result?.entries ?? const <ServerQueryRecord>[])
        if (item.client.isNotEmpty) item.client,
    }.toList()..sort();
    final selected = await showSheet<String>(
      context: context,
      builder: (_) => _ClientFilterSheet(clients: clients, selected: _client),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _client = selected;
      _page = 0;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.serverLogClearTitle,
        actions: [
          TextButton(
            onPressed: () => popFloatingDialog(context, false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => popFloatingDialog(context, true),
            child: Text(context.l10n.serverLogClear),
          ),
        ],
        child: Text(context.l10n.serverLogClearBody),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(serverControllerProvider.notifier).clearQueryLog();
      if (mounted) showAppSnack(context, context.l10n.serverLogCleared);
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(serverControllerProvider).value;
    final query = _query;
    final result = ref.watch(serverQueryLogProvider(query));
    final filtered =
        _domainQuery.isNotEmpty ||
        _client.isNotEmpty ||
        _status.isNotEmpty ||
        _qtype.isNotEmpty ||
        _rangeStartMs > 0;
    return CommonScaffold(
      title: context.l10n.serverLogsTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.serverLogClear,
          onPressed: _clear,
          icon: const Icon(TablerIcons.brush),
        ),
      ],
      body: PageBody(
        children: [
          // 统计是服务运行期的实时指标；停止时只展示已持久化的历史日志。
          if (snapshot != null && snapshot.status.running)
            _StatsOverview(stats: snapshot.stats),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: SearchField(
                    controller: _domain,
                    hintText: context.l10n.serverLogSearchDomain,
                    onChanged: _onDomainChanged,
                    onSubmitted: () => _applyDomain(_domain.text),
                  ),
                ),
                IconButton(
                  tooltip: _client.isEmpty
                      ? context.l10n.serverLogFilterClient
                      : context.l10n.serverLogClientFiltered(_client),
                  onPressed: () => _openClientFilter(
                    snapshot?.stats ?? const ServerStats(),
                    result.value,
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: _client.isEmpty
                        ? context.raisedSurfaceLevel.colorOf(
                            context.colorScheme,
                          )
                        : context.colorScheme.primaryContainer,
                    foregroundColor: _client.isEmpty
                        ? context.colorScheme.onSurfaceVariant
                        : context.colorScheme.onPrimaryContainer,
                  ),
                  icon: const Icon(TablerIcons.filter),
                ),
              ],
            ),
          ),
          if (_client.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  CommonChip(
                    label: _client,
                    onDeleted: () => setState(() {
                      _client = '';
                      _page = 0;
                    }),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: SegmentedControl<String>(
              segments: [
                ('', context.l10n.serverLogAll),
                ('blocked', context.l10n.serverLogBlocked),
                ('cached', context.l10n.serverLogCached),
                ('error', context.l10n.serverLogError),
              ],
              value: _status,
              onChanged: (value) => setState(() {
                _status = value;
                _page = 0;
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: SegmentedControl<String>(
                    segments: [
                      ('all', context.l10n.serverLogAll),
                      ('24h', context.l10n.serverLogRange24h),
                      ('7d', context.l10n.serverLogRange7d),
                    ],
                    value: _range,
                    onChanged: _setRange,
                  ),
                ),
                IconButton(
                  tooltip: _qtype.isEmpty
                      ? context.l10n.serverLogType
                      : '${context.l10n.serverLogType} · $_qtype',
                  onPressed: _openTypeFilter,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: _qtype.isEmpty
                        ? context.raisedSurfaceLevel.colorOf(
                            context.colorScheme,
                          )
                        : context.colorScheme.primaryContainer,
                    foregroundColor: _qtype.isEmpty
                        ? context.colorScheme.onSurfaceVariant
                        : context.colorScheme.onPrimaryContainer,
                  ),
                  icon: const Icon(TablerIcons.filter),
                ),
              ],
            ),
          ),
          result.when(
            data: (data) {
              if (data.entries.isEmpty) {
                return _EmptyLogCard(
                  title: filtered
                      ? context.l10n.serverLogNoMatchTitle
                      : context.l10n.serverLogEmpty,
                  body: filtered
                      ? context.l10n.serverLogNoMatchBody
                      : context.l10n.serverLogEmptyBody,
                );
              }
              return _Rows(
                result: data,
                page: _page,
                pageSize: _pageSize,
                onPage: (page) => setState(() => _page = page),
                onOpen: (record) => _showDetail(context, record),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CommonCircleLoading()),
            ),
            error: (error, _) => ServerErrorCard(
              message: error.toString(),
              onRetry: () => ref.invalidate(serverQueryLogProvider(query)),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, ServerQueryRecord record) {
    showFloatingDialog<void>(
      context: context,
      child: CommonDialog(
        title: record.domain,
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: record.domain));
              popFloatingDialog(context);
              showAppSnack(context, context.l10n.serverLogDomainCopied);
            },
            child: Text(context.l10n.serverLogCopyDomain),
          ),
          TextButton(
            onPressed: () => popFloatingDialog(context),
            child: Text(context.l10n.uiClose),
          ),
        ],
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KeyValueRow(
                label: context.l10n.serverLogTime,
                value: _formatTimestamp(record.timestamp),
                tabular: true,
              ),
              KeyValueRow(
                label: context.l10n.serverLogStatus,
                value: record.status,
              ),
              KeyValueRow(
                label: context.l10n.serverLogType,
                value: record.qtype,
              ),
              KeyValueRow(
                label: context.l10n.serverLogClient,
                value: record.client,
              ),
              KeyValueRow(
                label: context.l10n.serverLogProtocol,
                value: record.protocol,
              ),
              KeyValueRow(
                label: context.l10n.serverLogDuration,
                value: serverMs(record.durationMs),
                tabular: true,
              ),
              KeyValueRow(
                label: context.l10n.serverLogCache,
                value: record.cacheHit.isEmpty ? '—' : record.cacheHit,
              ),
              KeyValueRow(
                label: context.l10n.serverLogRcode,
                value: record.rcode.isEmpty ? '—' : record.rcode,
                tabular: true,
              ),
              KeyValueRow(
                label: context.l10n.serverLogTtl,
                value: record.ttl?.toString() ?? '—',
                tabular: true,
              ),
              KeyValueRow(
                label: context.l10n.serverLogUpstream,
                value: record.upstreamProvider.isEmpty
                    ? '—'
                    : record.upstreamProvider,
              ),
              if (record.filterRule.isNotEmpty)
                KeyValueRow(
                  label: context.l10n.serverLogRule,
                  value: record.filterRule,
                  tabular: true,
                ),
              if (record.filterReason.isNotEmpty)
                KeyValueRow(
                  label: context.l10n.serverLogRuleReason,
                  value: record.filterReason,
                ),
              if (record.error.isNotEmpty)
                KeyValueRow(
                  label: context.l10n.serverLogErrorField,
                  value: record.error,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
