import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_android/widgets/dashboard/dashboard_card.dart';
import 'package:diting_android/widgets/dashboard/dashboard_density.dart';
import 'package:diting_android/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/state/memory_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class MemoryCard extends ConsumerStatefulWidget {
  const MemoryCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  ConsumerState<MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends ConsumerState<MemoryCard>
    with PageVisibilityMixin<MemoryCard> {
  ProcessMemoryNotifier? _memory;
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
    return DashboardCard(
      semanticLabel: context.l10n.memoryTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: TablerIcons.cpu_2,
            title: context.l10n.memoryTitle,
            trailing: [
              if (widget.onDetail != null)
                DashboardIconButton(
                  glyph: TablerIcons.chevron_right,
                  tooltip: context.l10n.dashboardDetailTooltip,
                  onPressed: widget.onDetail,
                ),
            ],
          ),
          const _MemoryFigures(),
        ],
      ),
    );
  }
}

class _MemoryFigures extends ConsumerWidget {
  const _MemoryFigures();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(processMemoryProvider);
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final available = memory.available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 10 * scale),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: available ? dashboardBinaryBytes(memory.totalPss) : '—',
                style: DashboardText.figure(
                  context,
                  AppTextRole.metricSmall,
                  color: colorScheme.onSurface,
                ),
              ),
              if (available)
                TextSpan(text: '  PSS', style: DashboardText.unit(context)),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 10 * scale),
        _CompositionBar(
          segments: [
            (bytes: memory.javaHeap, color: colorScheme.primary),
            (bytes: memory.nativeHeap, color: colors.series2),
            (
              bytes: (memory.totalPss - memory.javaHeap - memory.nativeHeap)
                  .clamp(0, memory.totalPss),
              color: colors.track,
            ),
          ],
        ),
        SizedBox(height: 8 * scale),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _Legend(
              label: context.l10n.memoryJavaHeap,
              value: memory.javaHeap,
              color: colorScheme.primary,
              available: available,
            ),
            _Legend(
              label: context.l10n.memoryNativeHeap,
              value: memory.nativeHeap,
              color: colors.series2,
              available: available,
            ),
            if (available && memory.systemTotal > 0)
              _Legend(
                label: context.l10n.memorySystemAvailable,
                value: memory.systemAvail,
                color: colors.track,
                available: available,
                percentOf: memory.systemTotal,
              ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.label,
    required this.value,
    required this.color,
    required this.available,
    this.percentOf,
  });

  final String label;
  final int value;
  final Color color;
  final bool available;

  final int? percentOf;

  @override
  Widget build(BuildContext context) {
    final percentOf = this.percentOf;
    final String text;
    if (!available) {
      text = '—';
    } else if (percentOf == null || percentOf <= 0) {
      text = dashboardBinaryBytes(value);
    } else {
      text =
          '${dashboardBinaryBytes(value)}'
          '（${(value * 100 / percentOf).toStringAsFixed(0)}%）';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 5,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: ShapeDecoration(color: color, shape: AppShape.standard),
        ),
        Text(label, style: DashboardText.label(context)),
        Text(text, maxLines: 1, style: AppTextRole.numeric.of(context)),
      ],
    );
  }
}

class _CompositionBar extends StatelessWidget {
  const _CompositionBar({required this.segments});

  final List<({int bytes, Color color})> segments;

  @override
  Widget build(BuildContext context) {
    final scale = DashboardDensityScope.scaleOf(context);
    final total = segments.fold<int>(0, (sum, segment) => sum + segment.bytes);
    final height = 9.0 * scale;
    return ClipRSuperellipse(
      borderRadius: AppRadius.standard,
      child: SizedBox(
        height: height,
        child: total <= 0
            ? ColoredBox(color: DashboardColors.of(context).track)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final segment in segments)
                    if (segment.bytes > 0)
                      Expanded(
                        flex: (segment.bytes * 1000 ~/ total).clamp(1, 1000),
                        child: ColoredBox(color: segment.color),
                      ),
                ],
              ),
      ),
    );
  }
}
