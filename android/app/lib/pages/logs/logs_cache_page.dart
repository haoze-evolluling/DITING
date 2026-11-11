import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/dns_cache_repository.dart';
import 'package:diting_android/pages/logs/logs_cache_detail.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/log_refresh_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// DNS cache table from the real `dns_cache` table. The engine's in-memory LRU is authoritative;
/// `DnsCacheMirror` mirrors its top entries into this table every 10 s.
///
/// The mirror caps the table at 200 rows, but the page builds rows lazily anyway: reading a
/// bounded table eagerly is a latent trap, and every other bulk list in the app already behaves
/// this way.
class LogsCachePage extends ConsumerStatefulWidget {
  const LogsCachePage({super.key});

  @override
  ConsumerState<LogsCachePage> createState() => _LogsCachePageState();
}

class _LogsCachePageState extends ConsumerState<LogsCachePage>
    with PageVisibilityMixin<LogsCachePage> {
  final _search = TextEditingController();
  var _query = '';

  /// The native mirror rewrites `dns_cache` every 10 s; the list follows it without a tap.
  LogLiveRefreshNotifier? _logRefresh;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _logRefresh = ref.read(logLiveRefreshProvider.notifier);
  }

  @override
  void onPageVisibilityChanged(bool visible) {
    if (visible == _polling) return;
    _polling = visible;
    if (visible) {
      _logRefresh?.attachPolling();
    } else {
      _logRefresh?.detachPolling();
    }
  }

  @override
  void dispose() {
    if (_polling) _logRefresh?.detachPolling();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncEntries = ref.watch(dnsCacheProvider);
    return CommonScaffold(
      title: context.l10n.logsCacheTableTitle,
      searchState: AppBarSearchState(
        onSearch: (value) {
          final next = value.trim().toLowerCase();
          if (next == _query) return;
          setState(() => _query = next);
        },
      ),
      actions: [
        IconButton(
          tooltip: context.l10n.logsRefresh,
          onPressed: () => ref.read(dnsLogRevisionProvider.notifier).bump(),
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: _buildBody(asyncEntries),
    );
  }

  Widget _buildBody(AsyncValue<List<DnsCacheRecord>> asyncEntries) {
    // Check hasValue first: a refresh keeps the old value alongside isLoading, and
    // looking at isLoading alone would flash the loading state and lose scroll.
    if (!asyncEntries.hasValue) {
      if (asyncEntries.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              context.l10n.logsCacheLoadFailed('${asyncEntries.error}'),
              textAlign: TextAlign.center,
              style: context.listSubtitleStyle,
            ),
          ),
        );
      }
      return LogsPageLoading(label: context.l10n.logsLoadingCache);
    }
    final entries = _visible(asyncEntries.requireValue);
    // Last-hit time is a separate column because DnsCacheRecord has no lastHitAt.
    final lastHits = ref.watch(cacheLastHitProvider).value ?? const {};
    if (entries.isEmpty) {
      return SliverPageBody(
        slivers: [
          SliverToBoxAdapter(
            child: logsEmpty(
              label: _query.isEmpty ? context.l10n.logsCacheEmpty : context.l10n.logsCacheNoMatch,
              description: _query.isEmpty
                  ? context.l10n.logsCacheEmptyBody
                  : context.l10n.logsCurrentSearch(_query),
              illustration: NullStatusIllustration.dns,
            ),
          ),
        ],
      );
    }
    return SliverPageBody(
      slivers: [
        SliverToBoxAdapter(
          child: ListHeader(
            title: context.l10n.logsLiveCache,
            trailing: Text(
              context.l10n.logsEntryCount(entries.length),
              style: context.listCaptionStyle,
            ),
          ),
        ),
        ...lazySectionSlivers(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final lastHit = lastHits['${entry.domain}|${entry.queryType}'];
            return ListItem(
              leading: const GlyphIcon(AppGlyphs.layers),
              onTap: () => showSheet<void>(
                context: context,
                builder: (_) =>
                    DnsCacheDetailSheet(entry: entry, lastHitAt: lastHit),
              ),
              title: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      entry.domain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TonalChip(
                    label: dnsTypeName(entry.queryType),
                    color: context.raisedSurfaceLevel.colorOf(
                      context.colorScheme,
                    ),
                    foregroundColor: context.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(
                    context.l10n.logsCacheRow(
                      '${context.l10n.logsOriginalTtl} ${remainingLabel(entry.originalTtlSeconds, context.l10n)}',
                      entry.hitCount,
                      entry.responseSize,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    context.l10n.logsLastHitAt(
                      switch (lastHit) {
                        null => context.l10n.logsNeverHit,
                        final at => shortDateTimeOf(at),
                      },
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  Text(
                    '${context.l10n.logsRemainingTtl} ${remainingLabel(entry.remainingTtlSeconds, context.l10n)}',
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(
                          color:
                              entry.remainingTtlSeconds < cacheExpiringSeconds
                              ? context.colorScheme.warning
                              : context.colorScheme.success,
                        ),
                  ),
                  GlyphIcon(
                    AppGlyphs.chevronForward,
                    size: 18,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            );
          },
          footer:
              context.l10n.logsCacheFooterCount(entries.length),
        ),
      ],
    );
  }

  /// The mirror caps the table at 200 rows, so filtering here is cheaper than a second DB read.
  List<DnsCacheRecord> _visible(List<DnsCacheRecord> all) {
    if (_query.isEmpty) return all;
    return [
      for (final entry in all)
        if (entry.domain.toLowerCase().contains(_query)) entry,
    ];
  }
}
