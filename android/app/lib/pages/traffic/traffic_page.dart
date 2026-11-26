library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/db/app_traffic_repository.dart';
import 'package:diting_android/pages/observability/observability_common.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/traffic_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/app_list_view.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'traffic_filters.dart';
part 'traffic_rows.dart';

class TrafficPage extends ConsumerStatefulWidget {
  const TrafficPage({super.key});

  @override
  ConsumerState<TrafficPage> createState() => _TrafficPageState();
}

class _TrafficPageState extends ConsumerState<TrafficPage>
    with PageVisibilityMixin<TrafficPage> {
  final _search = TextEditingController();

  SpeedSeriesNotifier? _speed;
  bool _polling = false;

  bool _showTotals = false;

  @override
  void initState() {
    super.initState();
    _speed = ref.read(speedSeriesProvider.notifier);
  }

  @override
  void onPageVisibilityChanged(bool visible) {
    if (visible == _polling) return;
    _polling = visible;
    if (visible) {
      _speed?.attachPolling();
    } else {
      _speed?.detachPolling();
    }
  }

  @override
  void dispose() {
    if (_polling) _speed?.detachPolling();
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
          glyph: TablerIcons.brush,
          tooltip: context.l10n.trafficClearHistory,
          onPressed: () => _confirmClear(context),
        ),
        IconButtonData(
          glyph: TablerIcons.refresh,
          tooltip: context.l10n.trafficRefresh,
          onPressed: () => ref.read(dnsLogRevisionProvider.notifier).bump(),
        ),
        IconButtonData(
          glyph: TablerIcons.info_circle,
          tooltip: context.l10n.trafficAttribution,
          onPressed: _openAttributionSheet,
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
    final l10n = context.l10n;
    final visible = _ranked(
      snapshot.rows,
      sort,
      search,
      hideSystemApps: hideSystemApps,
    );
    final hiddenCount = hideSystemApps
        ? snapshot.rows
              .where((row) => isKnownSystemPackagePrefix(row.packageName))
              .length
        : 0;
    final totalsMode = _showTotals && window != TrafficWindow.all;
    final totals = totalsMode
        ? ref.watch(trafficSnapshotOfProvider(TrafficWindow.all)).asData?.value
        : null;
    final downBytes = totalsMode ? totals?.rxBytes : snapshot.rxBytes;
    final upBytes = totalsMode ? totals?.txBytes : snapshot.txBytes;
    final appCount = totalsMode ? totals?.rows.length : visible.length;

    return AppListScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: RepaintBoundary(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: CommonCard(
                    onPressed: window == TrafficWindow.all
                        ? null
                        : _toggleTotals,
                    child: StatStrip(
                      stats: [
                        StatItem(
                          label: totalsMode
                              ? l10n.trafficTotalDown
                              : l10n.trafficWindowDown(window.label(l10n)),
                          value: downBytes == null
                              ? '—'
                              : obsFormatBytes(downBytes),
                          color: context.colorScheme.primary,
                        ),
                        StatItem(
                          label: totalsMode
                              ? l10n.trafficTotalUp
                              : l10n.trafficWindowUp(window.label(l10n)),
                          value: upBytes == null
                              ? '—'
                              : obsFormatBytes(upBytes),
                        ),
                        StatItem(
                          label: l10n.trafficAppCount,
                          value: appCount == null ? '—' : '$appCount',
                          unit: appCount == null
                              ? null
                              : l10n.trafficAppCountUnit,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                _LiveRateCard(windowLabel: window.label(context.l10n)),
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
                      _explainUnavailable(
                        option.label,
                        option.unavailableReason,
                      );
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
                      label: search.isEmpty
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
            ),
          ),
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
              style: AppTextRole.supportingText.of(context),
            ),
          ),
        ),
      ],
    );
  }

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

  void _toggleTotals() {
    setState(() => _showTotals = !_showTotals);
  }

  void _openAttributionSheet() {
    showSheet<void>(
      context: context,
      builder: (_) => const _AttributionSheet(),
    );
  }

  void _explainUnavailable(String label, String? reason) {
    showAppSnack(
      context,
      context.l10n.trafficOptionUnavailable(
        label,
        reason ?? context.l10n.trafficNoSourceReason,
      ),
    );
  }

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
      showAppSnack(context, context.l10n.trafficCleared(deleted));
    } catch (error) {
      if (!context.mounted) return;
      showAppSnack(context, context.l10n.trafficClearFailed('$error'));
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
    return -result;
  });
  return filtered;
}
