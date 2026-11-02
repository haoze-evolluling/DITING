import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_android/data/site_latency_categories.dart';
import 'package:diting_android/data/site_latency_targets.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_parts.dart';
import 'package:diting_android/pages/home/dashboard/detail/site_latency_category_section.dart';
import 'package:diting_android/routes/home_detail_routes.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:diting_android/state/primary_provider_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Site latency detail: every site grouped by category, each group probed on demand. Nothing runs
/// on open — a page that probes 44 hosts on arrival both stalls and burns traffic — so the user
/// picks a category, or asks for everything with the app-bar action.
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
    return DashboardDetailScaffold(
      title: context.l10n.siteLatencyDetailTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.siteLatencyTestAll,
          onPressed: _anyProbing ? null : () => _probe(null),
          icon: const GlyphIcon(AppGlyphs.speed),
        ),
        IconButton(
          tooltip: context.l10n.siteLatencyCustomSites,
          onPressed: () => context.push(HomeDetailPaths.latencySites),
          icon: const GlyphIcon(AppGlyphs.customize),
        ),
      ],
      children: [
        DashboardDetailHero(
          glyph: AppGlyphs.target,
          label: context.l10n.siteLatencyConnectivity,
          value: _anyProbing
              ? context.l10n.siteLatencyTestingShort
              : measured.isEmpty
              ? context.l10n.siteLatencyNoTest
              : '$alive / ${measured.length}',
          chipLabel: _anyProbing
              ? context.l10n.siteLatencyInProgress
              : measured.isEmpty
              ? context.l10n.siteLatencyPending
              : failed == 0
              ? context.l10n.siteLatencyAllReachable
              : context.l10n.siteLatencyFailedCount(failed),
          chipColor: measured.isEmpty
              ? colorScheme.onSurfaceVariant
              : failed == 0
              ? colorScheme.success
              : colorScheme.warning,
          hint: _anyProbing
              ? context.l10n.siteLatencyTestingEach
              : measured.isEmpty
              ? context.l10n.siteLatencyPickCategory
              : '${context.l10n.siteLatencyLastRun(elapsedAgoLabel(_lastRunAt))}'
                    '${primary == null ? '' : context.l10n.siteLatencyProviderSuffix(primary.name)}',
        ),
        DashboardDetailCard(
          glyph: AppGlyphs.speed,
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
              StatItem(label: context.l10n.siteLatencyMeasuredSites, value: '${measured.length}'),
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

  /// Probes one category, or every category when [category] is null. Groups already running are
  /// skipped, so tapping another group's button while one is in flight does not restart it.
  Future<void> _probe(SiteCategory? category) async {
    final pending = category == null
        ? [
            for (final item in SiteCategory.values)
              if (!_probing.contains(item)) item,
          ]
        : _probing.contains(category)
        ? <SiteCategory>[]
        : [category];
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
