import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_chart.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_parts.dart';
import 'package:diting_android/state/memory_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Memory detail: the card can only show PSS and a three-part bar, so this page adds the device
/// view (how much of the phone is in use), the heap split as numbers instead of widths, and a
/// short PSS history to show whether memory is climbing while the tunnel runs.
class MemoryDetailPage extends ConsumerStatefulWidget {
  const MemoryDetailPage({super.key});

  @override
  ConsumerState<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends ConsumerState<MemoryDetailPage>
    with PageVisibilityMixin<MemoryDetailPage> {
  /// PSS history collected while the page is open; the provider only keeps the latest sample.
  static const _capacity = speedSampleCapacity;
  final List<double> _pss = [];

  ProcessMemoryNotifier? _memory;
  var _revision = 0;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _memory = ref.read(processMemoryProvider.notifier);
  }

  @override
  void onPageVisibilityChanged(bool visible) {
    if (visible == _polling) return;
    _polling = visible;
    if (visible) {
      _memory?.attachPolling();
    } else {
      _memory?.detachPolling();
    }
  }

  @override
  void dispose() {
    if (_polling) _memory?.detachPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memory = ref.watch(processMemoryProvider);
    ref.listen(processMemoryProvider, (previous, next) {
      if (!next.available) return;
      setState(() {
        _pss.add(next.totalPss.toDouble());
        if (_pss.length > _capacity) _pss.removeAt(0);
        _revision++;
      });
    });
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final available = memory.available;
    final other = (memory.totalPss - memory.javaHeap - memory.nativeHeap).clamp(
      0,
      memory.totalPss,
    );
    final deviceUsed = (memory.systemTotal - memory.systemAvail).clamp(
      0,
      memory.systemTotal,
    );
    return DashboardDetailScaffold(
      title: context.l10n.memoryDetailTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.memoryResample,
          onPressed: _memory == null ? null : () => _memory!.tick(),
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      children: [
        DashboardDetailHero(
          glyph: AppGlyphs.memory,
          label: context.l10n.memoryProcessPss,
          value: available ? dashboardBinaryBytes(memory.totalPss) : context.l10n.memoryUnavailable,
          chipLabel: available
              ? context.l10n.memorySystemShare(
                  dashboardPercent(memory.systemShare),
                )
              : context.l10n.commonNoData,
          chipColor: available
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          hint: available
              ? context.l10n.memorySystemUsedOf(
                  dashboardBinaryBytes(deviceUsed),
                  dashboardBinaryBytes(memory.systemTotal),
                )
              : context.l10n.memoryNoChannel,
        ),
        DashboardDetailStats(
          stats: [
            StatItem(
              label: context.l10n.memoryJavaHeap,
              value: available ? dashboardBinaryBytes(memory.javaHeap) : '—',
              color: colorScheme.primary,
            ),
            StatItem(
              label: context.l10n.memoryNativeHeap,
              value: available ? dashboardBinaryBytes(memory.nativeHeap) : '—',
              color: colors.series2,
            ),
            StatItem(
              label: context.l10n.memoryOther,
              value: available ? dashboardBinaryBytes(other) : '—',
            ),
            StatItem(
              label: context.l10n.memorySystemAvailable,
              value: available ? dashboardBinaryBytes(memory.systemAvail) : '—',
            ),
          ],
        ),
        DashboardDetailCard(
          glyph: AppGlyphs.layers,
          title: context.l10n.memoryComposition,
          footer: available
              ? context.l10n.memoryCompositionFooter
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              DashboardShareBar(
                segments: [
                  (
                    value: memory.javaHeap.toDouble(),
                    color: colorScheme.primary,
                  ),
                  (value: memory.nativeHeap.toDouble(), color: colors.series2),
                  (value: other.toDouble(), color: colors.track),
                ],
              ),
              DashboardShareLegend(
                label: context.l10n.memoryJavaHeap,
                value: available ? dashboardBinaryBytes(memory.javaHeap) : '—',
                color: colorScheme.primary,
                share: _share(memory.javaHeap, memory.totalPss),
              ),
              DashboardShareLegend(
                label: context.l10n.memoryNativeHeap,
                value: available
                    ? dashboardBinaryBytes(memory.nativeHeap)
                    : '—',
                color: colors.series2,
                share: _share(memory.nativeHeap, memory.totalPss),
              ),
              DashboardShareLegend(
                label: context.l10n.memoryOtherCode,
                value: available ? dashboardBinaryBytes(other) : '—',
                color: colors.track,
                share: _share(other, memory.totalPss),
              ),
            ],
          ),
        ),
        DashboardDetailCard(
          glyph: AppGlyphs.cpu,
          title: context.l10n.memorySystemSection,
          footer: available && memory.systemTotal > 0
              ? context.l10n.memorySystemFooter
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              DashboardShareBar(
                segments: [
                  (value: deviceUsed.toDouble(), color: colorScheme.primary),
                  (value: memory.systemAvail.toDouble(), color: colors.track),
                ],
              ),
              DashboardShareLegend(
                label: context.l10n.memorySystemUsed,
                value: available ? dashboardBinaryBytes(deviceUsed) : '—',
                color: colorScheme.primary,
                share: _share(deviceUsed, memory.systemTotal),
              ),
              DashboardShareLegend(
                label: context.l10n.memorySystemAvailable,
                value: available
                    ? dashboardBinaryBytes(memory.systemAvail)
                    : '—',
                color: colors.track,
                share: _share(memory.systemAvail, memory.systemTotal),
              ),
            ],
          ),
        ),
        DashboardDetailChart(
          title: context.l10n.memoryRecentPss,
          color: colorScheme.primary,
          values: _pss,
          revision: _revision,
          capacity: _capacity,
          // 16 MB floor: a flat idle line must not be blown up into noise.
          minScale: 16 * 1024 * 1024,
          height: 128,
          emptyLabel: context.l10n.memorySampling,
          caption: context.l10n.memoryRecentPssCaption,
        ),
        DashboardDetailNote(
          text: context.l10n.memorySourceFooter,
        ),
      ],
    );
  }

  static double? _share(int part, int total) =>
      total <= 0 ? null : (part / total).clamp(0.0, 1.0);
}
