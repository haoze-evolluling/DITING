import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_android/data/site_latency_categories.dart';
import 'package:diting_android/data/site_latency_targets.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_parts.dart';
import 'package:diting_android/pages/home/dashboard/detail/site_latency_category_section.dart';
import 'package:diting_android/routes/home_detail_routes.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:diting_android/state/primary_provider_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class SiteLatencyDetailPage extends ConsumerStatefulWidget {
  const SiteLatencyDetailPage({super.key});

  @override
  ConsumerState<SiteLatencyDetailPage> createState() =>
      _SiteLatencyDetailPageState();
}

class _SiteLatencyDetailPageState extends ConsumerState<SiteLatencyDetailPage> {
  final Map<String, PingSummary> _results = {};
  final Set<SiteCategory> _probing = {};
  DateTime? _lastRunAt;

  bool get _anyProbing => _probing.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final primary = ref.watch(primaryProviderProvider);
    final measured = _results.values.toList();
    final alive = measured.where((result) => result.success).length;
    final failed = measured.where((result) => !result.success).length;
    final averages = [for (final result in measured) ?result.avgMs];
    final average = averages.isEmpty
        ? null
        : averages.reduce((a, b) => a + b) / averages.length;
    final String connectivityValue;
    if (_anyProbing) {
      connectivityValue = context.l10n.siteLatencyTestingShort;
    } else if (measured.isEmpty) {
      connectivityValue = context.l10n.siteLatencyNoTest;
    } else {
      connectivityValue = '$alive / ${measured.length}';
    }
    final String chipLabel;
    if (_anyProbing) {
      chipLabel = context.l10n.siteLatencyInProgress;
    } else if (measured.isEmpty) {
      chipLabel = context.l10n.siteLatencyPending;
    } else if (failed == 0) {
      chipLabel = context.l10n.siteLatencyAllReachable;
    } else {
      chipLabel = context.l10n.siteLatencyFailedCount(failed);
    }
    final Color chipColor;
    if (measured.isEmpty) {
      chipColor = colorScheme.onSurfaceVariant;
    } else if (failed == 0) {
      chipColor = colorScheme.success;
    } else {
      chipColor = colorScheme.warning;
    }
    final String hint;
    if (_anyProbing) {
      hint = context.l10n.siteLatencyTestingEach;
    } else if (measured.isEmpty) {
      hint = context.l10n.siteLatencyPickCategory;
    } else {
      final providerSuffix = primary == null
          ? ''
          : context.l10n.siteLatencyProviderSuffix(primary.name);
      hint =
          '${context.l10n.siteLatencyLastRun(elapsedAgoLabel(_lastRunAt))}'
          '$providerSuffix';
    }
    return DashboardDetailScaffold(
      title: context.l10n.siteLatencyDetailTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.siteLatencyTestAll,
          onPressed: _anyProbing ? null : () => _probe(null),
          icon: const Icon(TablerIcons.gauge),
        ),
        IconButton(
          tooltip: context.l10n.siteLatencyCustomSites,
          onPressed: () => context.push(HomeDetailPaths.latencySites),
          icon: const Icon(TablerIcons.layout_grid_add),
        ),
      ],
      children: [
        DashboardDetailHero(
          glyph: TablerIcons.target,
          label: context.l10n.siteLatencyConnectivity,
          value: connectivityValue,
          chipLabel: chipLabel,
          chipColor: chipColor,
          hint: hint,
        ),
        DashboardDetailCard(
          glyph: TablerIcons.gauge,
          title: context.l10n.siteLatencyThisRun,
          child: DashboardStatGrid(
            stats: [
              StatItem(
                label: context.l10n.siteLatencyReachable,
                value: '$alive',
                color: colorScheme.success,
              ),
              StatItem(
                label: context.l10n.commonFailed,
                value: '$failed',
                color: failed > 0 ? colorScheme.error : null,
              ),
              StatItem(
                label: context.l10n.siteLatencySheetAverage,
                value: average == null ? '—' : '${average.round()}',
                unit: average == null ? null : 'ms',
              ),
              StatItem(
                label: context.l10n.siteLatencyMeasuredSites,
                value: '${measured.length}',
              ),
            ],
          ),
        ),
        for (final category in SiteCategory.values)
          SiteLatencyCategorySection(
            category: category,
            targets: siteLatencyInCategory(category),
            results: _results,
            probing: _probing.contains(category),
            lastRunAt: _lastRunAt,
            onProbe: () => _probe(category),
          ),
        DashboardDetailNote(text: context.l10n.siteLatencyDetailFooterLong),
      ],
    );
  }

  Future<void> _probe(SiteCategory? category) async {
    final List<SiteCategory> pending;
    if (category == null) {
      pending = [
        for (final item in SiteCategory.values)
          if (!_probing.contains(item)) item,
      ];
    } else if (_probing.contains(category)) {
      pending = const [];
    } else {
      pending = [category];
    }
    if (pending.isEmpty) return;
    final targets = [
      for (final item in pending) ...siteLatencyInCategory(item),
    ];
    setState(() {
      _probing.addAll(pending);
      for (final target in targets) {
        _results.remove(target.id);
      }
    });
    final runner = ref.read(diagnosticsRunnerProvider);
    final summaries = await Future.wait([
      for (final target in targets)
        runner.ping(target.host, count: 3, timeoutSeconds: 2),
    ]);
    if (!mounted) return;
    setState(() {
      _probing.removeAll(pending);
      _lastRunAt = DateTime.now();
      for (final (index, summary) in summaries.indexed) {
        _results[targets[index].id] = summary;
      }
    });
  }
}
