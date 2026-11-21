import 'dart:math' as math;

import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

part 'dashboard_connected_buttons.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    this.padding,
    this.onTap,
    this.semanticLabel,
    this.clipBehavior = Clip.none,
    required this.child,
  });

  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  final Clip clipBehavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final shape = AppShape.standard;
    final editBar = DashboardEditBar.of(context);
    final content = RepaintBoundary(
      child: Padding(
        padding: padding ?? dashboardCardPadding(density),
        child: editBar == null
            ? child
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: DashboardEditBar.height, child: editBar),
                  const SizedBox(height: DashboardEditBar.gap),
                  IgnorePointer(
                    child: DisabledMask(status: true, child: child),
                  ),
                ],
              ),
      ),
    );
    final scoped = SurfaceScope(level: SurfaceLevel.card, child: content);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        clipBehavior: clipBehavior,
        decoration: ShapeDecoration(
          color: DashboardColors.of(context).card,
          shape: shape,
          shadows: DashboardShadows.e1(context),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: onTap == null || editBar != null
              ? scoped
              : FocusRing(
                  shape: shape,
                  child: InkWell(
                    customBorder: shape,
                    onTap: onTap,
                    child: scoped,
                  ),
                ),
        ),
      ),
    );
  }
}

class DashboardEditBar extends InheritedWidget {
  const DashboardEditBar({super.key, required this.bar, required super.child});

  static const height = 28.0;
  static const gap = 10.0;

  final Widget bar;

  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardEditBar>()?.bar;

  @override
  bool updateShouldNotify(DashboardEditBar oldWidget) => bar != oldWidget.bar;
}

class DashboardCardHeader extends StatelessWidget {
  const DashboardCardHeader({
    super.key,
    this.glyph,
    required this.title,
    this.leading = const [],
    this.trailing = const [],
    this.chevron = false,
  });

  static const height = 24.0;
  static const glyphSize = 18.0;

  final IconData? glyph;
  final String title;

  final List<Widget> leading;
  final List<Widget> trailing;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final style = DashboardText.cardTitle(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: Row(
        spacing: 8,
        children: [
          if (glyph case final glyph?)
            Icon(
              glyph,
              size: glyphSize,
              color: colorScheme.onSurfaceVariant,
            ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
                ...leading,
              ],
            ),
          ),
          for (final child in trailing)
            SizedBox(
              height: height,
              child: Center(child: child),
            ),
          if (chevron)
            Icon(
              TablerIcons.chevron_right,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

class DashboardBlock extends StatelessWidget {
  const DashboardBlock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: color ?? DashboardColors.of(context).tone,
        shape: AppShape.standard,
      ),
      child: child,
    );
  }
}

enum DashboardChipTone { idle, ok, warn }

class DashboardChip extends StatelessWidget {
  const DashboardChip({
    super.key,
    required this.label,
    this.tone = DashboardChipTone.idle,
    this.dot = false,
    this.large = false,
  });

  final String label;
  final DashboardChipTone tone;
  final bool dot;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final (foreground, background) = switch (tone) {
      DashboardChipTone.idle => (colorScheme.onSurfaceVariant, colors.tone),
      DashboardChipTone.ok => (colorScheme.success, colors.tone),
      DashboardChipTone.warn => (colorScheme.warning, colors.tone),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 8,
        vertical: large ? 5 : 3,
      ),
      decoration: ShapeDecoration(color: background, shape: AppShape.standard),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          if (dot)
            Container(
              width: 6,
              height: 6,
              decoration: ShapeDecoration(
                color: foreground,
                shape: AppShape.standard,
              ),
            ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (large ? AppTextRole.sectionLabel : AppTextRole.badge)
                  .of(context)
                  .toTabular
                  .copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardMetric extends StatelessWidget {
  const DashboardMetric({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.style = AppTextRole.metricCompact,
  });

  final String label;
  final String value;
  final Color? color;

  final AppTextRole style;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.figure(context, style, color: color),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
      ],
    );
  }
}

class DashboardMetricGrid extends StatelessWidget {
  const DashboardMetricGrid({
    super.key,
    required this.metrics,
    this.maxColumns = 4,
    this.gap = 16,
    this.runGap = 14,
  });

  final List<DashboardMetric> metrics;

  final int maxColumns;

  final double gap;
  final double runGap;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final columns = scale >= 1.2 ? math.min(2, maxColumns) : maxColumns;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = math.max(1, math.min(columns, metrics.length));
        final cellWidth = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: runGap,
          children: [
            for (final metric in metrics)
              SizedBox(width: cellWidth, child: metric),
          ],
        );
      },
    );
  }
}

class DashboardSwitch extends StatelessWidget {
  const DashboardSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CommonSwitch.trackWidth,
      height: CommonSwitch.trackHeight,
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: CommonSwitch(
          value: value,
          onChanged: onChanged,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

class DashboardIconButton extends StatelessWidget {
  const DashboardIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    this.onPressed,
    this.size = 32,
    this.glyphSize = 18,
  });

  final IconData glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: OverflowBox(
        minHeight: size,
        maxHeight: size,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: glyphSize,
          style: IconButton.styleFrom(
            minimumSize: Size.square(size),
            fixedSize: Size.square(size),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: context.colorScheme.onSurfaceVariant,
          ),
          onPressed: onPressed,
          icon: Icon(glyph, size: glyphSize),
        ),
      ),
    );
  }
}

class DashboardCardEntrance extends StatelessWidget {
  const DashboardCardEntrance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, amount, child) => Opacity(
        opacity: amount,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - amount)),
          child: child,
        ),
      ),
      child: RepaintBoundary(child: child),
    );
  }
}
