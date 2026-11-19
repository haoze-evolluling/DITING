import 'dart:async';

import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
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
  final _domain = TextEditingController();
  final _client = TextEditingController();
  Timer? _timer;
  String _status = '';
  int _page = 0;

  ServerLogQuery get _query => ServerLogQuery(
    domain: _domain.text.trim(),
    client: _client.text.trim(),
    status: _status,
    limit: _pageSize,
    offset: _page * _pageSize,
  );

  @override
  void onPageVisibilityChanged(bool visible) {
    _timer?.cancel();
    _timer = visible
        ? Timer.periodic(const Duration(seconds: 5), (_) {
            ref.read(serverControllerProvider.notifier).refreshLive();
          })
        : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _domain.dispose();
    _client.dispose();
    super.dispose();
  }

  void _search() {
    setState(() => _page = 0);
    ref.read(serverLogRevisionProvider.notifier).bump();
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
    final result = ref.watch(serverQueryLogProvider(_query));
    return CommonScaffold(
      title: context.l10n.serverLogsTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.serverLogClear,
          onPressed: _clear,
          icon: const GlyphIcon(AppGlyphs.broom),
        ),
      ],
      body: PageBody(
        children: [
          if (snapshot != null) _StatsOverview(stats: snapshot.stats),
          _Filters(
            domain: _domain,
            client: _client,
            status: _status,
            onSearch: _search,
            onStatus: (value) {
              setState(() {
                _status = value;
                _page = 0;
              });
            },
          ),
          result.when(
            data: (data) => _Rows(
              result: data,
              page: _page,
              pageSize: _pageSize,
              onPage: (page) => setState(() => _page = page),
              onOpen: (record) => _showDetail(context, record),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CommonCircleLoading()),
            ),
            error: (error, _) => ServerErrorCard(
              message: error.toString(),
              onRetry: _search,
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
                const GlyphIcon(AppGlyphs.block, size: 16),
                Expanded(
                  child: Text(
                    stats.topBlockedDomains
                        .take(3)
                        .map((item) => '${item.name} (${item.count})')
                        .join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1.of(context),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.domain,
    required this.client,
    required this.status,
    required this.onSearch,
    required this.onStatus,
  });

  final TextEditingController domain;
  final TextEditingController client;
  final String status;
  final VoidCallback onSearch;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextField(
                  controller: domain,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSearch(),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: context.l10n.serverLogSearchDomain,
                    prefixIcon: const GlyphIcon(AppGlyphs.search, size: 18),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: client,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSearch(),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: context.l10n.serverLogSearchClient,
                    prefixIcon: const GlyphIcon(AppGlyphs.devices, size: 18),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.l10n.serverLogSearch,
                onPressed: onSearch,
                icon: const GlyphIcon(AppGlyphs.search),
              ),
            ],
          ),
          SegmentedControl<String>(
            segments: [
              ('', context.l10n.serverLogAll),
              ('blocked', context.l10n.serverLogBlocked),
              ('cached', context.l10n.serverLogCached),
              ('error', context.l10n.serverLogError),
            ],
            value: status,
            onChanged: onStatus,
          ),
        ],
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
    if (result.entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: NullStatus(label: context.l10n.serverLogEmpty),
      );
    }
    final pages = (result.total / pageSize).ceil();
    final scheme = context.colorScheme;
    return Column(
      children: [
        for (final record in result.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 0),
            child: CommonCard(
              onPressed: () => onOpen(record),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                spacing: 10,
                children: [
                  GlyphIcon(
                    record.blocked
                        ? AppGlyphs.block
                        : record.cached
                        ? AppGlyphs.database
                        : AppGlyphs.checkCircle,
                    size: 18,
                    color: record.blocked ? scheme.error : scheme.primary,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          record.domain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.listTitleStyle,
                        ),
                        Text(
                          '${record.qtype} · ${record.client.isEmpty ? '—' : record.client}'
                          ' · ${record.upstreamProvider.isEmpty ? '—' : record.upstreamProvider}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.listSubtitleStyle,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    serverMs(record.durationMs),
                    style: AppTextStyle.caption1.of(context).copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: appTabularFigures,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.serverLogPage(page + 1, pages.clamp(1, 1 << 30)),
                  style: AppTextStyle.caption1.of(context).copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                onPressed: page > 0 ? () => onPage(page - 1) : null,
                icon: const GlyphIcon(AppGlyphs.chevronBack, size: 18),
              ),
              IconButton(
                onPressed: page + 1 < pages ? () => onPage(page + 1) : null,
                icon: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
