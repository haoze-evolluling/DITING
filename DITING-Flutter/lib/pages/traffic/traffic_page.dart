/// Traffic stats: time window plus per-app ranking, read from `app_traffic_daily`.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/db/app_traffic_repository.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/pages/observability/observability_common.dart';
import 'package:diting/state/dashboard_providers.dart';
import 'package:diting/state/log_providers.dart';
import 'package:diting/state/traffic_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/app_icon_avatar.dart';
import 'package:diting/widgets/app_list_view.dart';
import 'package:diting/widgets/chip_row.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'traffic_filters.dart';
part 'traffic_rows.dart';

class TrafficPage extends ConsumerStatefulWidget {
  const TrafficPage({super.key});

  @override
  ConsumerState<TrafficPage> createState() => _TrafficPageState();
}

class _TrafficPageState extends ConsumerState<TrafficPage> {
  final _search = TextEditingController();

  /// Grab the notifier on entry: dispose() cannot call ref.read.
  SpeedSeriesNotifier? _speed;

  /// Explanatory tips show on the first visit only; the app bar info button keeps the
  /// attribution explainer reachable afterwards.
  late final bool _showTips;

  @override
  void initState() {
    super.initState();
    _showTips = consumeTrafficTips(ref.read(legacyPrefsStoreProvider));
    // Shares the same rate series as the home page; the provider ref-counts it.
    _speed = ref.read(speedSeriesProvider.notifier);
    _speed!.attachPolling();
  }

  @override
  void dispose() {
    _speed?.detachPolling();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncSnapshot = ref.watch(trafficSnapshotProvider);
    final window = ref.watch(trafficWindowProvider);
    final sort = ref.watch(trafficSortProvider);
    final search = ref.watch(trafficSearchProvider);
    final hideSystemApps = ref.watch(trafficHideSystemAppsProvider);

    return CommonScaffold(
      title: context.l10n.trafficTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.broom,
          tooltip: context.l10n.trafficClearHistory,
          onPressed: () => _confirmClear(context),
        ),
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: context.l10n.trafficRefresh,
          onPressed: () => ref.read(dnsLogRevisionProvider.notifier).bump(),
        ),
        IconButtonData(
          glyph: AppGlyphs.info,
          tooltip: context.l10n.trafficAttribution,
          onPressed: () => showSheet<void>(
            context: context,
            builder: (_) => const _AttributionSheet(),
          ),
        ),
      ],
      body: _body(context, asyncSnapshot, window, sort, search, hideSystemApps),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncValue<TrafficSnapshot> asyncSnapshot,
    TrafficWindow window,
    TrafficSort sort,
    String search,
    bool hideSystemApps,
  ) {
    if (!asyncSnapshot.hasValue && asyncSnapshot.hasError) {
      return ObsFailure(
        label: context.l10n.trafficLoadFailed,
        description: '${asyncSnapshot.error}',
        onRetry: () => ref.read(dnsLogRevisionProvider.notifier).bump(),
      );
    }
    if (!asyncSnapshot.hasValue) {
      return ObservabilityLoading(label: context.l10n.trafficLoading);
    }

    final snapshot = asyncSnapshot.requireValue;
    final visible = _ranked(
      snapshot.rows,
      sort,
      search,
      hideSystemApps: hideSystemApps,
    );
    final hiddenCount =
        snapshot.rows.length - _ranked(snapshot.rows, sort, search).length;

    return AppListScrollView(
      slivers: [
        // The header is a box adapter, which gets no repaint boundary of its own.
        SliverToBoxAdapter(
          child: RepaintBoundary(child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: StatStrip(
                  stats: [
                    StatItem(
                      label: context.l10n.trafficWindowDown(
                        window.label(context.l10n),
                      ),
                      value: obsFormatBytes(snapshot.rxBytes),
                      color: context.colorScheme.primary,
                    ),
                    StatItem(
                      label: context.l10n.trafficWindowUp(
                        window.label(context.l10n),
                      ),
                      value: obsFormatBytes(snapshot.txBytes),
                    ),
                    StatItem(
                      label: context.l10n.trafficAppCount,
                      value: '${visible.length}',
                      unit: context.l10n.trafficAppCountUnit,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                // Range chips go through ChipRow: a bare Wrap gives no cross-axis constraint
                // and wraps, pushing every card below it down.
                child: ChipRow(
                  children: [
                    for (final option in _rangeOptions(context.l10n))
                      FilterPill(
                        label: option.label,
                        selected: option.window == window,
                        disabled: option.unavailableReason != null,
                        onPressed: () {
                          final target = option.window;
                          if (target == null) {
                            _explainUnavailable(
                              option.label,
                              option.unavailableReason,
                            );
                          } else {
                            ref
                                .read(trafficWindowProvider.notifier)
                                .select(target);
                          }
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _LiveRateCard(
                windowLabel: window.label(context.l10n),
                showNote: _showTips,
              ),
              if (_showTips) ...[
                const SizedBox(height: 10),
                _AttributionBanner(
                  onTap: () => showSheet<void>(
                    context: context,
                    builder: (_) => const _AttributionSheet(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _TrafficFilterBar(
                searchController: _search,
                sort: sort,
                hideSystemApps: hideSystemApps,
                onSearchChanged: (value) => ref
                    .read(trafficSearchProvider.notifier)
                    .setQuery(value.trim()),
                onSortSelected: (option) {
                  final target = option.sort;
                  if (target == null) {
                    _explainUnavailable(option.label, option.unavailableReason);
                  } else {
                    ref.read(trafficSortProvider.notifier).select(target);
                  }
                },
                onHideSystemAppsChanged: (value) => ref
                    .read(trafficHideSystemAppsProvider.notifier)
                    .setValue(value),
              ),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: NullStatus(
                    label: search.isEmpty && !hideSystemApps
                        ? context.l10n.trafficNoData
                        : context.l10n.trafficNoMatchingApps,
                    description: _emptyDescription(
                      l10n: context.l10n,
                      search: search,
                      hideSystemApps: hideSystemApps,
                      hiddenCount: hiddenCount,
                      window: window,
                    ),
                    illustration: NullStatusIllustration.data,
                  ),
                ),
            ],
          )),
        ),
        if (visible.isNotEmpty)
          ...appListSlivers(
            title: context.l10n.trafficRankingTitle,
            itemCount: visible.length,
            footer: context.l10n.trafficShareWindow(
                  window.label(context.l10n),
                  _windowLabel(snapshot, context.l10n),
                ),
            itemBuilder: (context, index) {
              final row = visible[index];
              return AppTrafficRow(
                row: row,
                total: snapshot.totalBytes,
                sort: sort,
                onTap: () => showSheet<void>(
                  context: context,
                  builder: (_) => _AppTrafficDetailSheet(
                    row: row,
                    total: snapshot.totalBytes,
                    sort: sort,
                  ),
                ),
              );
            },
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              context.l10n.trafficTotalApps(
                visible.length,
                obsFormatBytes(snapshot.totalBytes),
              ),
              style: context.listCaptionStyle,
            ),
          ),
        ),
      ],
    );
  }

  /// Empty-state text, distinguishing no data from filtered-out and hidden-system.
  static String _emptyDescription({
    required AppL10n l10n,
    required String search,
    required bool hideSystemApps,
    required int hiddenCount,
    required TrafficWindow window,
  }) {
    if (search.isNotEmpty) return l10n.trafficSearchEmpty(search);
    if (hideSystemApps && hiddenCount > 0) {
      return l10n.trafficHiddenCount(hiddenCount);
    }
    if (window == TrafficWindow.all) {
      return l10n.trafficNoRecordsBody;
    }
    return l10n.trafficNoRecordsForWindow(window.label(l10n));
  }

  /// Disabled option explanation. A hint bar rather than silence: a tap must answer.
  void _explainUnavailable(String label, String? reason) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.trafficOptionUnavailable(
            label,
            reason ?? context.l10n.trafficNoSourceReason,
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Clear history: the confirmation wording is copied verbatim from upstream. The async
  /// guard uses the passed context.mounted, which pairs with the context the analyzer sees.
  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.trafficClearTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => popFloatingDialog(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => popFloatingDialog(context, true),
            child: Text(context.l10n.trafficConfirmClear),
          ),
        ],
        child: Text(context.l10n.trafficClearBody),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final deleted = await ref
          .read(trafficClearHistoryProvider.notifier)
          .clear();
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.trafficCleared(deleted)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.trafficClearFailed('$error')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static String _windowLabel(TrafficSnapshot snapshot, AppL10n l10n) {
    if (snapshot.startDate.isEmpty) return l10n.trafficRangeAllHistory;
    if (snapshot.startDate == snapshot.endDate) {
      return l10n.trafficWindowLabelDate(snapshot.startDate);
    }
    return l10n.trafficWindowLabelRange(snapshot.startDate, snapshot.endDate);
  }
}

/// Sort, keyword filter and system-app hiding, all in Dart rather than a second SQL pass: a
/// month of history is a few hundred rows, and one sort definition avoids disagreeing with
/// the ranking query's ORDER BY.
List<AppTrafficDaily> _ranked(
  List<AppTrafficDaily> rows,
  TrafficSort sort,
  String search, {
  bool hideSystemApps = false,
}) {
  final query = search.toLowerCase();
  final filtered = <AppTrafficDaily>[
    for (final row in rows)
      if (!(hideSystemApps && isKnownSystemPackagePrefix(row.packageName)) &&
          (query.isEmpty ||
              row.appName.toLowerCase().contains(query) ||
              row.packageName.toLowerCase().contains(query)))
        row,
  ];
  filtered.sort((a, b) {
    final result = switch (sort) {
      TrafficSort.total => a.totalBytes.compareTo(b.totalBytes),
      TrafficSort.download => a.rxBytes.compareTo(b.rxBytes),
      TrafficSort.upload => a.txBytes.compareTo(b.txBytes),
    };
    // Descending, matching the SQL: ascending would put the least-used app first.
    return -result;
  });
  return filtered;
}
