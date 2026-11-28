part of 'server_logs_page.dart';

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

class _LogFilterSelection {
  const _LogFilterSelection({
    required this.status,
    required this.range,
    required this.qtype,
    required this.client,
  });

  static const empty = _LogFilterSelection(
    status: '',
    range: 'all',
    qtype: '',
    client: '',
  );

  final String status;
  final String range;
  final String qtype;
  final String client;

  int get activeCount =>
      (status.isEmpty ? 0 : 1) +
      (range == 'all' ? 0 : 1) +
      (qtype.isEmpty ? 0 : 1) +
      (client.isEmpty ? 0 : 1);

  bool get isActive => activeCount > 0;

  _LogFilterSelection copyWith({
    String? status,
    String? range,
    String? qtype,
    String? client,
  }) {
    return _LogFilterSelection(
      status: status ?? this.status,
      range: range ?? this.range,
      qtype: qtype ?? this.qtype,
      client: client ?? this.client,
    );
  }
}

class _LogFilterSheet extends StatefulWidget {
  const _LogFilterSheet({
    required this.initial,
    required this.clients,
    required this.onChanged,
  });

  static const _types = ['', 'A', 'AAAA', 'CNAME', 'HTTPS', 'TXT', 'MX', 'NS'];

  final _LogFilterSelection initial;
  final List<String> clients;
  final ValueChanged<_LogFilterSelection> onChanged;

  @override
  State<_LogFilterSheet> createState() => _LogFilterSheetState();
}

class _LogFilterSheetState extends State<_LogFilterSheet> {
  late _LogFilterSelection _selection = widget.initial;

  void _select(_LogFilterSelection next) {
    setState(() => _selection = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.serverLogFilter,
      body: ListView(
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          ListHeader(title: l10n.serverLogStatus),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedControl<String>(
              segments: [
                ('', l10n.serverLogAll),
                ('blocked', l10n.serverLogBlocked),
                ('cached', l10n.serverLogCached),
                ('error', l10n.serverLogError),
              ],
              value: _selection.status,
              onChanged: (value) => _select(_selection.copyWith(status: value)),
            ),
          ),
          ListHeader(title: l10n.serverLogRange),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedControl<String>(
              segments: [
                ('all', l10n.serverLogAll),
                ('24h', l10n.serverLogRange24h),
                ('7d', l10n.serverLogRange7d),
              ],
              value: _selection.range,
              onChanged: (value) => _select(_selection.copyWith(range: value)),
            ),
          ),
          generateSection(
            title: l10n.serverLogType,
            items: [
              for (final type in _LogFilterSheet._types)
                ListItem(
                  leading: Icon(
                    type.isEmpty ? TablerIcons.list : TablerIcons.tag,
                    size: 20,
                  ),
                  title: Text(type.isEmpty ? l10n.serverLogAll : type),
                  trailing: _selection.qtype == type
                      ? const SelectionCheck()
                      : null,
                  onTap: () => _select(_selection.copyWith(qtype: type)),
                ),
            ],
          ),
          generateSection(
            title: l10n.serverLogClient,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.devices, size: 20),
                title: Text(l10n.serverLogClientAll),
                trailing: _selection.client.isEmpty
                    ? const SelectionCheck()
                    : null,
                onTap: () => _select(_selection.copyWith(client: '')),
              ),
              for (final client in widget.clients)
                ListItem(
                  leading: const Icon(TablerIcons.devices, size: 20),
                  title: Text(
                    client,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _selection.client == client
                      ? const SelectionCheck()
                      : null,
                  onTap: () => _select(_selection.copyWith(client: client)),
                ),
            ],
            footer: widget.clients.isEmpty ? l10n.serverLogClientEmpty : null,
          ),
          if (_selection.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TonalButton(
                label: l10n.serverLogFilterReset,
                glyph: TablerIcons.restore,
                onPressed: () => _select(_LogFilterSelection.empty),
              ),
            ),
        ],
      ),
    );
  }
}
