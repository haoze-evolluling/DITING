/// The query log as a table: search, one status filter, and offset paging, all of it answered by
/// `/api/v1/querylog/search`.
///
/// Android's request feed scrolls a `ListView` and loads the next page when the end comes into
/// view. A desktop window shows the same rows as a table with a visible pager, so the reader can
/// see where they are in a result set the service counts for them (`total`), instead of guessing
/// from a scroll position.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/data/api/desktop_log_providers.dart';
import 'package:diting/desktop/pages/home/desktop_format.dart';
import 'package:diting/desktop/pages/logs/log_format.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Column widths of the wide table; the domain column takes what is left.
const double _timeWidth = 68;
const double _statusWidth = 22;
const double _typeWidth = 52;
const double _clientWidth = 132;
const double _latencyWidth = 66;

/// The empty state's box. [NullStatus] aligns and scrolls, so it needs a height of its own inside
/// a card that otherwise sizes to its rows.
const double _emptyHeight = 260;

class LogQueryTable extends ConsumerStatefulWidget {
  const LogQueryTable({super.key, required this.wide, required this.onRetry});

  /// Whether there is room for the time, type and client columns.
  final bool wide;

  final VoidCallback onRetry;

  @override
  ConsumerState<LogQueryTable> createState() => _LogQueryTableState();
}

class _LogQueryTableState extends ConsumerState<LogQueryTable> {
  /// Every keystroke would otherwise issue a search against the service; 250 ms is the debounce
  /// Android's request feed uses.
  static const _searchDebounce = Duration(milliseconds: 250);

  final _search = TextEditingController();
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      ref.read(desktopLogQueryProvider.notifier).setDomain(value);
    });
  }

  void _reset() {
    _searchTimer?.cancel();
    _search.clear();
    ref.read(desktopLogQueryProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final feed = ref.watch(desktopLogFeedProvider);
    final query = ref.watch(desktopLogQueryProvider);
    // `value` keeps the previous page while the next one is in flight, so the table does not
    // collapse to a spinner every time the reader turns a page.
    final page = feed.value;
    final rows = page?.entries ?? const <QueryLogEntry>[];
    final total = page?.total ?? 0;

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
          _Filters(
            controller: _search,
            onChanged: _onSearch,
            wide: widget.wide,
          ),
          const SizedBox(height: 8),
          _body(context, feed, query, rows),
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
  }

  Widget _body(
    BuildContext context,
    AsyncValue<QueryLogPage> feed,
    DesktopLogQuery query,
    List<QueryLogEntry> rows,
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
              ? l10n.obsCurrentFilter(_filterLabel(context, query))
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
        if (widget.wide) const _TableHeader(),
        for (final (index, entry) in rows.indexed) ...[
          if (index > 0 || widget.wide) const _RowDivider(),
          _LogRow(entry: entry, wide: widget.wide),
        ],
        if (feed.hasError) ...[
          const _RowDivider(),
          _Failure(error: '${feed.error}', onRetry: widget.onRetry),
        ],
      ],
    );
  }
}

/// The active filter in words, for the empty state's description. Uses the same labels the
/// filter itself shows, so the two cannot disagree.
String _filterLabel(BuildContext context, DesktopLogQuery query) => [
  if (query.status != DesktopLogStatus.all) _statusLabel(context, query.status),
  if (query.domain.isNotEmpty) query.domain,
].join(' · ');

String _statusLabel(BuildContext context, DesktopLogStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    DesktopLogStatus.all => l10n.commonAll,
    DesktopLogStatus.passed => l10n.logPassed,
    DesktopLogStatus.blocked => l10n.logBlocked,
    DesktopLogStatus.cached => l10n.logCacheHits,
    DesktopLogStatus.error => l10n.logFailed,
  };
}

class _Filters extends ConsumerWidget {
  const _Filters({
    required this.controller,
    required this.onChanged,
    required this.wide,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final query = ref.watch(desktopLogQueryProvider);
    final search = SearchField(
      controller: controller,
      hintText: l10n.desktopLogSearchHint,
      onChanged: onChanged,
      onSubmitted: () => ref
          .read(desktopLogQueryProvider.notifier)
          .setDomain(controller.text),
    );
    final status = _StatusPicker(query: query);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [search, Align(alignment: AlignmentDirectional.centerStart, child: status)],
      );
    }
    return Row(
      spacing: 10,
      children: [
        Expanded(flex: 3, child: search),
        status,
        if (query.isFiltered)
          TextButton(
            onPressed: () {
              controller.clear();
              ref.read(desktopLogQueryProvider.notifier).reset();
            },
            child: Text(l10n.obsClearFilter),
          ),
      ],
    );
  }
}

/// The status filter, shaped like Android's window picker: a label, a chevron and a menu of
/// checked entries.
class _StatusPicker extends ConsumerWidget {
  const _StatusPicker({required this.query});

  final DesktopLogQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final color = query.isFiltered
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return CommonPopupBox(
      targetBuilder: (open) => Semantics(
        button: true,
        label: context.l10n.obsStatus,
        child: InkWell(
          customBorder: AppShape.all(AppCorner.sm),
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                GlyphIcon(AppGlyphs.filter, size: 16, color: color),
                Text(
                  _statusLabel(context, query.status),
                  style: AppTextStyle.callout.of(context).copyWith(color: color),
                ),
                GlyphIcon(AppGlyphs.chevronDown, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
      popupBuilder: (_) => CommonPopupMenu(
        items: [
          for (final status in DesktopLogStatus.values)
            CommonPopupMenuItem(
              label: _statusLabel(context, status),
              checked: status == query.status,
              onPressed: () =>
                  ref.read(desktopLogQueryProvider.notifier).setStatus(status),
            ),
        ],
      ),
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
          SizedBox(width: _timeWidth, child: Text(l10n.obsTime, style: style)),
          const SizedBox(width: _statusWidth),
          Expanded(child: Text(l10n.desktopLogDomain, style: style)),
          SizedBox(width: _typeWidth, child: Text(l10n.obsProtocol, style: style)),
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
      QueryLogEntry(cached: true) => (AppGlyphs.checkCircle, colorScheme.success),
      QueryLogEntry(status: 'error') => (AppGlyphs.error, colorScheme.error),
      _ => (AppGlyphs.arrowUp, colorScheme.onSurfaceVariant),
    };
    final label = DashboardText.label(context);
    // Padding rather than a fixed height: enlarged text grows the row instead of clipping it.
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
            child: Row(
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

/// `1-25 / 1,234` plus two page buttons. Both ends are disabled when there is nothing to turn to,
/// because the service already told the page how many rows exist.
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
          // A page exists only while a full page still fits after this one.
          onPressed: query.offset + DesktopLogQuery.pageSize >= total
              ? null
              : onNext,
          child: Text(l10n.desktopLogPageNext),
        ),
      ],
    );
  }
}

/// A failed search with a retry, in place of the rows. Kept to one row so a transient failure does
/// not push the pager off the card.
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
