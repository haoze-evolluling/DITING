import 'dart:async';

import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
  int _page = 0;

  ServerLogQuery get _query => ServerLogQuery(
    domain: _domainQuery,
    client: _client,
    status: _status,
    limit: _pageSize,
    offset: _page * _pageSize,
  );

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
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
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
    final running = snapshot?.status.running == true;
    final filtered =
        _domainQuery.isNotEmpty || _client.isNotEmpty || _status.isNotEmpty;
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
          if (snapshot != null) _StatsOverview(stats: snapshot.stats),
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
          result.when(
            data: (data) {
              if (!running) {
                return _EmptyLogCard(
                  title: context.l10n.serverLogStoppedTitle,
                  body: context.l10n.serverLogStoppedBody,
                );
              }
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

String _formatTimestamp(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

class _StatsOverview extends StatelessWidget {
  const _StatsOverview({required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: CommonCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: StatStrip(
              stats: [
                StatItem(
                  label: context.l10n.serverQueries,
                  value: serverCount(stats.queries),
                ),
                StatItem(
                  label: context.l10n.serverBlocked,
                  value: serverCount(stats.blocked),
                ),
                StatItem(
                  label: context.l10n.serverBlockRate,
                  value: serverPercent(stats.blockedRate),
                ),
                StatItem(
                  label: context.l10n.serverAverageLatency,
                  value: stats.averageResponseMs.toStringAsFixed(0),
                  unit: 'ms',
                ),
              ],
            ),
          ),
        ),
        if (stats.topBlockedDomains.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              spacing: 8,
              children: [
                const Icon(TablerIcons.ban, size: 16),
                Expanded(
                  child: Text(
                    stats.topBlockedDomains
                        .take(3)
                        .map((item) => '${item.name} (${item.count})')
                        .join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextRole.caption.of(context),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyLogCard extends StatelessWidget {
  const _EmptyLogCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            IconBadge(
              glyph: TablerIcons.logs,
              size: 38,
              glyphSize: 19,
              color: context.raisedSurfaceLevel.colorOf(scheme),
              foregroundColor: scheme.onSurfaceVariant,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(title, style: AppTextRole.rowTitle.of(context)),
                  Text(body, style: AppTextRole.supportingText.of(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({
    required this.result,
    required this.page,
    required this.pageSize,
    required this.onPage,
    required this.onOpen,
  });

  final ServerQueryResult result;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPage;
  final ValueChanged<ServerQueryRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final pages = (result.total / pageSize).ceil();
    final scheme = context.colorScheme;
    return Column(
      children: [
        generateSection(
          title: context.l10n.serverLogResults,
          items: [
            for (final record in result.entries)
              ListItem(
                leading: Icon(
                  record.blocked
                      ? TablerIcons.ban
                      : record.cached
                      ? TablerIcons.database
                      : TablerIcons.circle_check,
                  size: 18,
                  color: record.blocked
                      ? scheme.error
                      : record.cached
                      ? scheme.primary
                      : scheme.success,
                ),
                title: Text(
                  record.domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${record.qtype.isEmpty ? '—' : record.qtype}'
                  ' · ${record.client.isEmpty ? '—' : record.client}'
                  ' · ${record.upstreamProvider.isEmpty ? '—' : record.upstreamProvider}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  serverMs(record.durationMs),
                  style: AppTextRole.caption
                      .of(context)
                      .copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: appTabularFigures,
                      ),
                ),
                onTap: () => onOpen(record),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.serverLogPage(page + 1, pages.clamp(1, 1 << 30)),
                  style: AppTextRole.caption
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              IconButton(
                onPressed: page > 0 ? () => onPage(page - 1) : null,
                icon: const Icon(TablerIcons.chevron_left, size: 18),
              ),
              IconButton(
                onPressed: page + 1 < pages ? () => onPage(page + 1) : null,
                icon: const Icon(TablerIcons.chevron_right, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClientFilterSheet extends StatelessWidget {
  const _ClientFilterSheet({required this.clients, required this.selected});

  final List<String> clients;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.serverLogFilterClient,
      body: ListView(
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          generateSection(
            title: context.l10n.serverLogClient,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.devices, size: 20),
                title: Text(context.l10n.serverLogClientAll),
                trailing: selected.isEmpty ? const SelectionCheck() : null,
                onTap: () => Navigator.of(context).pop(''),
              ),
              for (final client in clients)
                ListItem(
                  leading: const Icon(TablerIcons.devices, size: 20),
                  title: Text(
                    client,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: selected == client ? const SelectionCheck() : null,
                  onTap: () => Navigator.of(context).pop(client),
                ),
            ],
            footer: clients.isEmpty ? context.l10n.serverLogClientEmpty : null,
          ),
        ],
      ),
    );
  }
}
