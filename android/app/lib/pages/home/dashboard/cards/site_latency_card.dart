import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_android/data/site_latency_targets.dart';
import 'package:diting_android/pages/home/dashboard/cards/site_latency_sheet.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:diting_android/state/primary_provider_providers.dart';
import 'package:diting_android/state/site_latency_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class SiteLatencyCard extends ConsumerStatefulWidget {
  const SiteLatencyCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  ConsumerState<SiteLatencyCard> createState() => _SiteLatencyCardState();
}

class _SiteLatencyCardState extends ConsumerState<SiteLatencyCard> {
  final Map<String, PingSummary> _results = {};
  var _probing = false;
  DateTime? _lastRunAt;

  var _autoRan = false;

  Timer? _autoProbeTimer;

  @override
  void initState() {
    super.initState();
    if (debugDisableDashboardLiveUpdates) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoRan) return;
      _autoRan = true;
      // 冷启动首帧后立即并发探测会和用户第一次滑动争抢资源，
      // 稍作延迟并在滑动结束后再自动测速。
      _autoProbeTimer = Timer(
        const Duration(milliseconds: 1500),
        () => ScrollActivityGate.whenIdle(() {
          if (mounted) unawaited(_probe());
        }),
      );
    });
  }

  @override
  void dispose() {
    _autoProbeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    final primary = ref.watch(primaryProviderProvider);
    final sites = ref.watch(dashboardSitesProvider);

    final measured = sites
        .where((site) => _results.containsKey(site.id))
        .length;
    final alive = sites
        .where((site) => _results[site.id]?.success ?? false)
        .length;
    final String verdict;
    if (_probing) {
      verdict = context.l10n.siteLatencyTesting;
    } else if (measured == 0) {
      verdict = context.l10n.siteLatencyNotTested;
    } else {
      verdict = context.l10n.siteLatencyAliveRatio(alive, sites.length);
    }
    final DashboardChipTone tone;
    if (_probing || measured == 0) {
      tone = DashboardChipTone.idle;
    } else if (alive == sites.length) {
      tone = DashboardChipTone.ok;
    } else {
      tone = DashboardChipTone.warn;
    }
    return DashboardCard(
      semanticLabel: context.l10n.siteLatencyTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: TablerIcons.target,
            title: context.l10n.siteLatencyTitle,
            leading: [DashboardChip(label: verdict, tone: tone, dot: true)],
            trailing: [
              if (widget.onDetail != null)
                DashboardIconButton(
                  glyph: TablerIcons.chevron_right,
                  tooltip: context.l10n.dashboardDetailTooltip,
                  onPressed: widget.onDetail,
                ),
              DashboardIconButton(
                glyph: TablerIcons.refresh,
                tooltip: context.l10n.siteLatencyRetest,
                onPressed: _probing ? null : _probe,
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          for (var i = 0; i < sites.length; i += _columns)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8 * scale),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  for (final target in sites.skip(i).take(_columns))
                    Expanded(
                      child: _SiteCell(
                        target: target,
                        summary: _results[target.id],
                        probing: _probing,
                        onTap: () => showSheet<void>(
                          context: context,
                          builder: (_) => SiteLatencyTargetSheet(
                            target: target,
                            summary: _results[target.id],
                            lastRunAt: _lastRunAt,
                          ),
                        ),
                      ),
                    ),
                  if (sites.length - i < _columns) const Spacer(),
                ],
              ),
            ),
          SizedBox(height: 8 * scale),
          Text(
            '${context.l10n.siteLatencyLastRun(elapsedAgoLabel(_lastRunAt))}'
            '${primary == null ? '' : context.l10n.siteLatencyProviderSuffix(primary.name)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(
              context,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static const _columns = 2;

  Future<void> _probe() async {
    if (_probing) return;
    final sites = ref.read(dashboardSitesProvider);
    setState(() {
      _probing = true;
      _results.clear();
    });
    final runner = ref.read(diagnosticsRunnerProvider);
    final summaries = await Future.wait([
      for (final target in sites)
        runner.ping(target.host, count: 3, timeoutSeconds: 2),
    ]);
    if (!mounted) return;
    setState(() {
      _probing = false;
      _lastRunAt = DateTime.now();
      for (final (index, summary) in summaries.indexed) {
        _results[sites[index].id] = summary;
      }
    });
  }
}

class _SiteCell extends StatelessWidget {
  const _SiteCell({
    required this.target,
    required this.summary,
    required this.probing,
    required this.onTap,
  });

  final SiteLatencyTarget target;
  final PingSummary? summary;
  final bool probing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final scale = DashboardDensityScope.scaleOf(context);
    final failed = summary != null && !summary!.success;
    final pending = probing || summary == null;
    final Color dotColor;
    if (pending) {
      dotColor = colorScheme.outline;
    } else if (failed) {
      dotColor = colorScheme.error;
    } else {
      dotColor = colorScheme.success;
    }
    final (status, statusColor) = switch (summary) {
      _ when probing => (
        context.l10n.siteLatencyTesting,
        colorScheme.onSurfaceVariant,
      ),
      null => (context.l10n.siteLatencyNotTested, colorScheme.onSurfaceVariant),
      final s when !s.success => (context.l10n.commonFailed, colorScheme.error),
      final s => (_latencyLabel(s, context.l10n), colorScheme.success),
    };
    return Semantics(
      button: true,
      label: '${target.name} $status',
      child: DashboardBlock(
        padding: EdgeInsets.fromLTRB(
          10 * scale,
          10 * scale,
          10 * scale,
          9 * scale,
        ),
        child: InkWell(
          customBorder: AppShape.standard,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                spacing: 6,
                children: [
                  _Badge(icon: target.icon, dot: dotColor),
                  Expanded(
                    child: Text(
                      target.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardText.rowTitle(context),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6 * scale),
              Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.sectionLabel
                    .of(context)
                    .copyWith(color: statusColor),
              ),
              Text(
                target.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.label(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _latencyLabel(PingSummary summary, AppL10n l10n) {
    final avg = summary.avgMs;
    if (avg == null) return l10n.siteLatencyNoReply;
    final rounded = avg.round();
    return summary.measuredWithFallback ? '$rounded ms*' : '$rounded ms';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.dot});

  final SiteIcon icon;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final scale = DashboardDensityScope.scaleOf(context);
    final size = 26.0 * scale;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: ShapeDecoration(
              color: DashboardColors.of(context).card,
              shape: AppShape.standard,
            ),
            child: Center(
              child: SiteIconView(
                icon,
                size: size * 0.6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 8,
              height: 8,
              decoration: ShapeDecoration(color: dot, shape: AppShape.standard),
            ),
          ),
        ],
      ),
    );
  }
}
