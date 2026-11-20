library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/data/api/desktop_log_providers.dart';
import 'package:diting_desktop/pages/home/desktop_format.dart';
import 'package:diting_desktop/pages/logs/log_format.dart';
import 'package:diting_desktop/pages/logs/widgets/log_filters.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _timeWidth = 68;
const double _statusWidth = 22;
const double _typeWidth = 52;
const double _clientWidth = 132;
const double _latencyWidth = 66;

const double _emptyHeight = 260;

const double _wideBreakpoint = 560;

class LogQueryTable extends ConsumerStatefulWidget {
  const LogQueryTable({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  ConsumerState<LogQueryTable> createState() => _LogQueryTableState();
}

class _LogQueryTableState extends ConsumerState<LogQueryTable> {
  static const _searchDebounce = Duration(milliseconds: 250);

  final _domain = TextEditingController();
  final _client = TextEditingController();
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _domain.dispose();
    _client.dispose();
    super.dispose();
  }

  ValueChanged<String> _debounced(void Function(String value) apply) =>
      (String value) {
        _searchTimer?.cancel();
        _searchTimer = Timer(_searchDebounce, () {
          if (!mounted) return;
          apply(value);
        });
      };

  void _reset() {
    _searchTimer?.cancel();
    _domain.clear();
    _client.clear();
    ref.read(desktopLogQueryProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final feed = ref.watch(desktopLogFeedProvider);
    final query = ref.watch(desktopLogQueryProvider);
    final page = feed.value;
    final rows = page?.entries ?? const <QueryLogEntry>[];
    final total = page?.total ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        return DashboardCard(
          semanticLabel: l10n.obsRecordsHeader,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardCardHeader(
                glyph: AppGlyphs.logs,
                title: l10n.obsRecordsHeader,
                leading: [
                  if (feed.isLoading)
                    const SizedBox.square(
                      dimension: 14,
                      child: CommonCircleLoading(),
                    )
                  else
                    DashboardChip(
                      label: dashboardCount(total),
                      tone: DashboardChipTone.idle,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LogFilterBar(
                domain: _domain,
                client: _client,
                wide: wide,
                onDomainChanged: _debounced(
                  ref.read(desktopLogQueryProvider.notifier).setDomain,
                ),
                onClientChanged: _debounced(
                  ref.read(desktopLogQueryProvider.notifier).setClient,
                ),
              ),
              const SizedBox(height: 8),
              _body(context, feed, query, rows, wide),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 6),
                _Pager(
                  query: query,
                  total: total,
                  shown: rows.length,
                  onPrevious: () =>
                      ref.read(desktopLogQueryProvider.notifier).previousPage(),
                  onNext: () => ref
                      .read(desktopLogQueryProvider.notifier)
                      .nextPage(total),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    AsyncValue<QueryLogPage> feed,
    DesktopLogQuery query,
    List<QueryLogEntry> rows,
    bool wide,
  ) {
    final l10n = context.l10n;
    if (rows.isEmpty) {
      if (feed.hasError) {
        return _Failure(error: '${feed.error}', onRetry: widget.onRetry);
      }
      if (feed.isLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CommonCircleLoading(size: 22)),
        );
      }
      return SizedBox(
        height: _emptyHeight,
        child: NullStatus(
          illustration: NullStatusIllustration.requests,
          label: query.isFiltered
              ? l10n.obsNoMatchingRequests
              : l10n.logRecentRequestsEmpty,
          description: query.isFiltered
              ? l10n.obsCurrentFilter(logFilterLabel(context, query))
              : null,
          action: query.isFiltered
              ? FilledButton.tonal(
                  onPressed: _reset,
                  child: Text(l10n.obsResetFilter),
                )
              : null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) const _TableHeader(),
        for (final (index, entry) in rows.indexed) ...[
          if (index > 0 || wide) const _RowDivider(),
          _LogRow(entry: entry, wide: wide),
        ],
        if (feed.hasError) ...[
          const _RowDivider(),
          _Failure(error: '${feed.error}', onRetry: widget.onRetry),
        ],
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = DashboardText.label(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            width: _timeWidth,
            child: Text(l10n.obsTime, style: style),
          ),
          const SizedBox(width: _statusWidth),
          Expanded(child: Text(l10n.desktopLogDomain, style: style)),
          SizedBox(
            width: _typeWidth,
            child: Text(l10n.obsProtocol, style: style),
          ),
          SizedBox(
            width: _clientWidth,
            child: Text(
              l10n.desktopLogClient,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          SizedBox(
            width: _latencyWidth,
            child: Text(
              l10n.logsAverageElapsed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.wide});

  final QueryLogEntry entry;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final (glyph, color) = switch (entry) {
      QueryLogEntry(blocked: true) => (AppGlyphs.block, colorScheme.error),
      QueryLogEntry(cached: true) => (
        AppGlyphs.checkCircle,
        colorScheme.success,
      ),
      QueryLogEntry(status: 'error') => (AppGlyphs.error, colorScheme.error),
      _ => (AppGlyphs.arrowUp, colorScheme.onSurfaceVariant),
    };
    final label = DashboardText.label(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        spacing: 8,
        children: [
          if (wide)
            SizedBox(
              width: _timeWidth,
              child: Text(
                desktopClock(entry.timestamp),
                maxLines: 1,
                style: label,
              ),
            ),
          SizedBox(
            width: _statusWidth,
            child: GlyphIcon(glyph, size: 16, color: color),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    Flexible(
                      child: Text(
                        entry.displayDomain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardText.rowTitle(context),
                      ),
                    ),
                    if (!wide && entry.qtype.isNotEmpty)
                      Text(entry.qtype, maxLines: 1, style: label),
                  ],
                ),
                if (!wide && entry.client.isNotEmpty)
                  Text(
                    entry.client,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: label,
                  ),
              ],
            ),
          ),
          if (wide)
            SizedBox(
              width: _typeWidth,
              child: Text(entry.qtype, maxLines: 1, style: label),
            ),
          if (wide)
            SizedBox(
              width: _clientWidth,
              child: Text(
                entry.client,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: label,
              ),
            ),
          SizedBox(
            width: _latencyWidth,
            child: Text(
              entry.blocked
                  ? l10n.statusBlocked
                  : entry.cached
                  ? l10n.logRowCacheHit
                  : desktopLatency(entry.durationMs),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: label,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    color: context.colorScheme.onSurface.withValues(alpha: 0.06),
  );
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.query,
    required this.total,
    required this.shown,
    required this.onPrevious,
    required this.onNext,
  });

  final DesktopLogQuery query;
  final int total;
  final int shown;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final from = total == 0 ? 0 : query.offset + 1;
    final to = query.offset + shown;
    return Row(
      spacing: 6,
      children: [
        TextButton(
          onPressed: query.offset == 0 ? null : onPrevious,
          child: Text(l10n.desktopLogPagePrev),
        ),
        Expanded(
          child: Text(
            l10n.desktopLogPageInfo('$from', '$to', dashboardCount(total)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: DashboardText.label(context),
          ),
        ),
        TextButton(
          onPressed: query.offset + DesktopLogQuery.pageSize >= total
              ? null
              : onNext,
          child: Text(l10n.desktopLogPageNext),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          GlyphIcon(AppGlyphs.warning, size: 18, color: colorScheme.warning),
          Expanded(
            child: Text(
              '${l10n.obsLoadFailed} · $error',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.rowTitle(context),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.desktopRetry)),
        ],
      ),
    );
  }
}
