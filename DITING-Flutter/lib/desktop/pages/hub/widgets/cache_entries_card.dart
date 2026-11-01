/// The cached names as a table: a server-side search over name and record type, a client-side
/// state filter, and the TTL each entry has left.
///
/// The old desktop console's `CacheEntriesTable.vue` is the blueprint. The search goes to
/// `/api/v1/cache/entries` (the service counts the total); the four chips only narrow the page that
/// already came back, because that is what the console does and re-querying would change `total`.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_cache_models.dart';
import 'package:diting/desktop/data/api/desktop_cache_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/cache_common.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _typeWidth = 64;
const double _statusWidth = 96;
const double _ttlWidth = 92;
const double _hitsWidth = 64;

/// Below this the initial TTL and the address column are dropped; the rest still fits.
const double _wideBreakpoint = 760;

class CacheEntriesCard extends ConsumerStatefulWidget {
  const CacheEntriesCard({super.key});

  @override
  ConsumerState<CacheEntriesCard> createState() => _CacheEntriesCardState();
}

class _CacheEntriesCardState extends ConsumerState<CacheEntriesCard> {
  /// Every keystroke would otherwise issue a search against the service; 250 ms matches the log
  /// page's own debounce.
  static const _searchDebounce = Duration(milliseconds: 250);

  final _search = TextEditingController();
  Timer? _timer;
  DesktopCacheEntryFilter _filter = DesktopCacheEntryFilter.all;

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _debouncedSearch(String value) {
    _timer?.cancel();
    _timer = Timer(_searchDebounce, () {
      if (!mounted) return;
      ref.read(desktopCacheSearchProvider.notifier).set(value);
    });
  }

  void _submitSearch() {
    _timer?.cancel();
    ref.read(desktopCacheSearchProvider.notifier).set(_search.text);
  }

  void _reset() {
    _timer?.cancel();
    _search.clear();
    setState(() => _filter = DesktopCacheEntryFilter.all);
    ref.read(desktopCacheSearchProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final feed = ref.watch(desktopCacheEntriesProvider);
    final query = ref.watch(desktopCacheSearchProvider);
    final page = feed.value;
    final rows = [
      for (final entry in page?.entries ?? const <DesktopCacheEntry>[])
        if (_filter.matches(entry)) entry,
    ];
    return DashboardCard(
      semanticLabel: l10n.desktopCacheEntriesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: l10n.desktopCacheEntriesTitle,
            leading: [
              if (feed.isLoading)
                const SizedBox.square(
                  dimension: 14,
                  child: CommonCircleLoading(),
                )
              else
                DashboardChip(label: '${page?.total ?? 0}'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopCacheEntriesBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: SearchField(
                  controller: _search,
                  hintText: l10n.desktopCacheEntriesSearch,
                  onChanged: _debouncedSearch,
                  onSubmitted: _submitSearch,
                ),
              ),
              if (query.isNotEmpty || _filter != DesktopCacheEntryFilter.all)
                TextButton(onPressed: _reset, child: Text(l10n.obsClearFilter)),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedControl<DesktopCacheEntryFilter>(
            value: _filter,
            segments: [
              for (final filter in DesktopCacheEntryFilter.values)
                (filter, desktopCacheFilterLabel(context, filter)),
            ],
            onChanged: (filter) => setState(() => _filter = filter),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) => _table(
              context,
              feed,
              rows,
              query,
              wide: constraints.maxWidth >= _wideBreakpoint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(
    BuildContext context,
    AsyncValue<DesktopCacheEntries> feed,
    List<DesktopCacheEntry> rows,
    String query, {
    required bool wide,
  }) {
    final l10n = context.l10n;
    if (feed.hasError && rows.isEmpty) {
      return _Failure(error: '${feed.error}', onRetry: _submitSearch);
    }
    if (rows.isEmpty) {
      if (feed.isLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CommonCircleLoading(size: 22)),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          query.isEmpty && _filter == DesktopCacheEntryFilter.all
              ? l10n.desktopCacheEntriesNone
              : l10n.desktopCacheEntriesEmpty,
          textAlign: TextAlign.center,
          style: DashboardText.label(context),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        wide ? const _Header() : const _CompactHeader(),
        for (final (index, entry) in rows.indexed) ...[
          if (index > 0 || wide) const _Divider(),
          _Row(entry: entry, wide: wide),
        ],
        if (feed.hasError) ...[
          const _Divider(),
          _Failure(error: '${feed.error}', onRetry: _submitSearch),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = DashboardText.label(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 8,
        children: [
          Expanded(child: Text(l10n.desktopCacheEntryDomain, style: style)),
          SizedBox(
            width: _typeWidth,
            child: Text(l10n.desktopCacheEntryType, style: style),
          ),
          SizedBox(
            width: _statusWidth,
            child: Text(l10n.desktopCacheEntryStatus, style: style),
          ),
          SizedBox(
            width: _ttlWidth,
            child: Text(
              l10n.desktopCacheEntryRemaining,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
          SizedBox(
            width: _ttlWidth,
            child: Text(
              l10n.desktopCacheEntryTtl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
          SizedBox(
            width: _hitsWidth,
            child: Text(
              l10n.desktopCacheEntryHits,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              l10n.desktopCacheEntryIps,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = DashboardText.label(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 8,
        children: [
          Expanded(child: Text(l10n.desktopCacheEntryDomain, style: style)),
          SizedBox(
            width: _typeWidth,
            child: Text(l10n.desktopCacheEntryType, style: style),
          ),
          SizedBox(
            width: _statusWidth,
            child: Text(l10n.desktopCacheEntryStatus, style: style),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.wide});

  final DesktopCacheEntry entry;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final label = DashboardText.label(context);
    final status = DashboardChip(
      label: desktopCacheStatusLabel(context, entry),
      tone: desktopCacheStatusTone(entry),
    );
    if (!wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    entry.domain,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.rowTitle(context),
                  ),
                ),
                SizedBox(
                  width: _typeWidth,
                  child: Text(entry.qtype, maxLines: 1, style: label),
                ),
              ],
            ),
            Row(
              spacing: 8,
              children: [
                status,
                const Spacer(),
                Text(
                  '${entry.remainingTtl}s',
                  maxLines: 1,
                  style: label.copyWith(
                    color: entry.remainingTtl > 0
                        ? colorScheme.onSurface
                        : colorScheme.warning,
                  ),
                ),
                Text('${entry.hitCount}', maxLines: 1, style: label),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              entry.domain,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.rowTitle(context),
            ),
          ),
          SizedBox(
            width: _typeWidth,
            child: Text(entry.qtype, maxLines: 1, style: label),
          ),
          SizedBox(
            width: _statusWidth,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: status,
            ),
          ),
          SizedBox(
            width: _ttlWidth,
            child: Text(
              '${entry.remainingTtl}s',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: label.copyWith(
                color: entry.remainingTtl > 0
                    ? colorScheme.onSurface
                    : colorScheme.warning,
              ),
            ),
          ),
          SizedBox(
            width: _ttlWidth,
            child: Text(
              '${entry.originalTtl}s',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: label,
            ),
          ),
          SizedBox(
            width: _hitsWidth,
            child: Text(
              '${entry.hitCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: label,
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              entry.ipList.isEmpty
                  ? l10n.desktopCacheNoIps
                  : entry.ipList.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: label,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    color: context.colorScheme.onSurface.withValues(alpha: 0.06),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          GlyphIcon(
            AppGlyphs.warning,
            size: 18,
            color: context.colorScheme.warning,
          ),
          Expanded(
            child: Text(
              '${l10n.desktopCacheEntriesLoadFailed} · $error',
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
