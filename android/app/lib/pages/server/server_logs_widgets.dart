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

class _TypeFilterSheet extends StatelessWidget {
  const _TypeFilterSheet({required this.selected, required this.types});

  final String selected;
  final List<String> types;

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.serverLogType,
      body: ListView(
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          generateSection(
            items: [
              for (final type in types)
                ListItem(
                  leading: Icon(
                    type.isEmpty ? TablerIcons.list : TablerIcons.tag,
                    size: 20,
                  ),
                  title: Text(type.isEmpty ? context.l10n.serverLogAll : type),
                  trailing: selected == type ? const SelectionCheck() : null,
                  onTap: () => Navigator.of(context).pop(type),
                ),
            ],
          ),
        ],
      ),
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
