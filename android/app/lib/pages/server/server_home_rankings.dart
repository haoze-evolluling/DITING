import 'dart:math' as math;

import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_home_parts.dart';
import 'package:diting_android/pages/server/server_home_style.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerTopDomainsOverview extends StatelessWidget {
  const ServerTopDomainsOverview({super.key, required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _RankingCard(
      glyph: TablerIcons.target,
      title: l10n.serverTopDomainsTitle,
      items: stats.topDomains.take(5).toList(),
      emptyText: l10n.serverNoRanking,
    );
  }
}

class ServerTopClientsOverview extends StatelessWidget {
  const ServerTopClientsOverview({super.key, required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _RankingCard(
      glyph: TablerIcons.devices,
      title: l10n.serverTopClientsTitle,
      items: stats.topClients.take(5).toList(),
      emptyText: l10n.serverNoRanking,
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.glyph,
    required this.title,
    required this.items,
    required this.emptyText,
  });

  final IconData glyph;
  final String title;
  final List<ServerNameCount> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final maxCount = items.isEmpty
        ? 1
        : items.map((item) => item.count).reduce(math.max);
    return ServerSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          ServerCardHeader(glyph: glyph, title: title),
          if (items.isEmpty)
            ServerEmptyPanel(
              glyph: glyph,
              title: emptyText,
              body: context.l10n.serverLast24Hours,
            )
          else
            for (final (index, item) in items.indexed)
              _RankingRow(rank: index + 1, item: item, maxCount: maxCount),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.item,
    required this.maxCount,
  });

  final int rank;
  final ServerNameCount item;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final progress = maxCount == 0
        ? 0.0
        : (item.count / maxCount).clamp(0.0, 1.0);
    final accent = ServerHomeColors.accent(context);
    final highlighted = rank == 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: highlighted
                ? ServerHomeColors.accentWash(context)
                : ServerHomeColors.track(context),
            shape: AppShape.standard,
          ),
          child: Text(
            '$rank',
            style: AppTextRole.badge
                .of(context)
                .toTabular
                .copyWith(
                  color: highlighted ? accent : scheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 7,
            children: [
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (rank == 1
                                  ? AppTextRole.bodyStrong
                                  : AppTextRole.supportingText)
                              .of(context),
                    ),
                  ),
                  Text(
                    serverCount(item.count),
                    style: AppTextRole.badge
                        .of(context)
                        .toTabular
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              ClipRRect(
                borderRadius: AppRadius.standard,
                child: Container(
                  height: 4,
                  color: ServerHomeColors.track(context),
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    heightFactor: 1,
                    child: ColoredBox(
                      color: highlighted
                          ? ServerHomeColors.accentStrong(context)
                          : ServerHomeColors.accentMuted(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ServerRecentQueries extends ConsumerWidget {
  const ServerRecentQueries({super.key, required this.running});

  final bool running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!running) return const SizedBox.shrink();
    final recent = ref.watch(
      serverQueryLogProvider(
        const ServerLogQuery(limit: 3, includeFile: false),
      ),
    );
    final scheme = context.colorScheme;
    final l10n = context.l10n;
    return ServerSectionCard(
      onPressed: () => context.go(ServerRoutes.logs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ServerCardHeader(
            glyph: TablerIcons.logs,
            title: l10n.serverRecentQueries,
            trailing: [
              Text(
                l10n.serverViewAll,
                style: AppTextRole.caption
                    .of(context)
                    .copyWith(color: scheme.primary),
              ),
              const Icon(TablerIcons.chevron_right, size: 17),
            ],
          ),
          recent.when(
            data: (result) => result.entries.isEmpty
                ? Text(
                    l10n.serverNoQueries,
                    style: AppTextRole.supportingText.of(context),
                  )
                : Column(
                    spacing: 4,
                    children: [
                      for (final record in result.entries)
                        _RecentQueryRow(record: record),
                    ],
                  ),
            loading: () => const Center(child: CommonCircleLoading(size: 18)),
            error: (error, _) => Text(
              error.toString(),
              style: AppTextRole.supportingText.of(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentQueryRow extends StatelessWidget {
  const _RecentQueryRow({required this.record});

  final ServerQueryRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = context.l10n;
    final color = record.blocked
        ? scheme.error
        : ServerHomeColors.accentStrong(context);
    final meta = [
      if (record.client.isNotEmpty) record.client,
      if (record.qtype.isNotEmpty) record.qtype,
      if (record.cached) l10n.serverLogCached,
      if (record.durationMs > 0) serverMs(record.durationMs),
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 11,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 7,
              height: 7,
              decoration: ShapeDecoration(
                color: record.blocked
                    ? scheme.error
                    : ServerHomeColors.accent(context),
                shape: AppShape.standard,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  record.domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextRole.sectionLabel.of(context),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextRole.micro
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Text(
            _statusLabel(context, record),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextRole.badge.of(context).copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(BuildContext context, ServerQueryRecord record) {
  if (record.blocked) return context.l10n.serverLogBlocked;
  if (record.cached) return context.l10n.serverLogCached;
  return switch (record.status) {
    'allowed' => context.l10n.serverAllowed,
    'error' => context.l10n.serverLogError,
    _ => record.status,
  };
}
