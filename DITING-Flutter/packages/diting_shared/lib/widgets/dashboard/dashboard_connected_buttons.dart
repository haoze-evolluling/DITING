part of 'dashboard_card.dart';

/// M3 Expressive connected button group: round ends, sharp inner edges, the selected
/// segment inflates into a full pill. A plain Row suffices where upstream uses RenderFlex.
class DashboardConnectedGroup extends StatelessWidget {
  const DashboardConnectedGroup({
    super.key,
    required this.children,
    this.spacing = 0,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: crossAxisAlignment,
      spacing: spacing,
      children: children,
    );
  }
}

class DashboardConnectedButton extends StatelessWidget {
  const DashboardConnectedButton({
    super.key,
    required this.selected,
    required this.first,
    required this.last,
    required this.outer,
    required this.inner,
    required this.background,
    required this.onTap,
    required this.semanticLabel,
    required this.builder,
  });

  final bool selected;
  final bool first;
  final bool last;
  final double outer;
  final double inner;
  final Color background;
  final VoidCallback onTap;
  final String semanticLabel;
  final Widget Function(Color foreground) builder;

  static const _selectDuration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final startRest = first ? outer : inner;
    final endRest = last ? outer : inner;
    final colorScheme = context.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: ElasticPress(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: selected ? 1 : 0, end: selected ? 1 : 0),
          duration: _selectDuration,
          curve: Curves.easeOutCubic,
          builder: (context, amount, child) {
            final start = startRest + (outer - startRest) * amount;
            final end = endRest + (outer - endRest) * amount;
            final shape = AppShape.of(
              BorderRadius.horizontal(
                left: Radius.circular(rtl ? end : start),
                right: Radius.circular(rtl ? start : end),
              ),
            );
            return FocusRing(
              shape: shape,
              standsOff: selected,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: Color.lerp(background, colorScheme.primary, amount),
                  shape: shape,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    customBorder: shape,
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    onTap: onTap,
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: builder(
            selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class DashboardSegmentedControl<T> extends StatelessWidget {
  const DashboardSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.outer = 26,
    this.inner = 12,
    this.height = 52,
  });

  final List<(T value, Glyph glyph, String label)> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double outer;
  final double inner;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tone = DashboardColors.of(context).tone;
    final style = AppTextStyle.footnote.of(context, emphasized: true);
    final scale = DashboardDensityScope.scaleOf(context);
    return DashboardConnectedGroup(
      children: [
        for (final (index, segment) in segments.indexed)
          Expanded(
            child: DashboardConnectedButton(
              selected: segment.$1 == value,
              first: index == 0,
              last: index == segments.length - 1,
              outer: outer,
              inner: inner,
              background: tone,
              semanticLabel: segment.$3,
              onTap: () => onChanged(segment.$1),
              builder: (foreground) => SizedBox(
                height: height * scale,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 2,
                  children: [
                    GlyphIcon(segment.$2, size: 18, color: foreground),
                    Text(
                      segment.$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
