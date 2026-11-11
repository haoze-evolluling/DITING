// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'navigation_dock.dart';

/// The pointer's highlight, drawn to the destination under it and leaning toward the cursor.
class _HoverHighlight extends StatelessWidget {
  const _HoverHighlight({
    required this.start,
    required this.width,
    required this.opacity,
  });

  final double start;
  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final alpha = _hoverAlpha * opacity.clamp(0.0, 1.0);
    if (alpha == 0) {
      return const SizedBox.shrink();
    }
    return Positioned.directional(
      textDirection: Directionality.of(context),
      start: start,
      top: 0,
      bottom: 0,
      width: width,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.colorScheme.onSurface.withValues(alpha: alpha),
          shape: AppShape.full,
        ),
      ),
    );
  }
}

class _Lens extends StatelessWidget {
  const _Lens({required this.rect, required this.lift, required this.glass});

  final Rect rect;
  final double lift;

  /// On glass the lens rests as a platter in the secondary hue, sunk in dark mode as iOS marks a
  /// tab.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final lifted = lift.clamp(0.0, 1.0);
    final tone = colorScheme.brightness == Brightness.dark ? 4.0 : 90.0;
    final hct = Hct.fromInt(colorScheme.secondary.toARGB32())..tone = tone;
    final platter = Color(hct.toInt()).withValues(alpha: 0.85);
    return PositionedDirectional(
      start: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: glass
              ? platter.withValues(alpha: platter.a * (1 - lifted))
              : Color.alphaBlend(
                  colorScheme.onSurface.withValues(alpha: 0.08 * lifted),
                  SurfaceLevel.floatingOf(colorScheme).next
                      .colorOf(colorScheme),
                ),
          shape: AppShape.full,
        ),
      ),
    );
  }
}

/// The clear lens a lifted selection becomes on glass. The destinations stand on it.
class _GlassLens extends StatelessWidget {
  const _GlassLens({required this.rect, required this.lift});

  final Rect rect;
  final double lift;

  @override
  Widget build(BuildContext context) {
    if (lift <= 0) {
      return const SizedBox.shrink();
    }
    final colorScheme = context.colorScheme;
    return Positioned.directional(
      textDirection: Directionality.of(context),
      start: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: LiquidGlass(
          style: LiquidGlassStyle.lens(colorScheme).scale(lift),
          shadows: _lensShadows(colorScheme, lift),
        ),
      ),
    );
  }
}

List<BoxShadow> _lensShadows(ColorScheme colorScheme, double lift) {
  final strength = colorScheme.brightness == Brightness.dark ? 3.0 : 1.0;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(
        alpha: 0.055 * strength * lift.clamp(0.0, 1.0),
      ),
      blurRadius: 5,
      offset: const Offset(0, 8),
    ),
  ];
}

/// What a lifted lens on glass shows of the destinations under it, with a pane of its own.
class _LensContent extends StatelessWidget {
  const _LensContent({
    required this.rect,
    required this.lift,
    required this.warp,
    required this.child,
  });

  final Rect rect;
  final double lift;
  final bool warp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final clipper = _LensClip(rect, textDirection);
    if (!warp) {
      return Positioned.fill(
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: ClipPath(clipper: clipper, child: child),
          ),
        ),
      );
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ClipPath(
            clipper: clipper,
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: child),
                Positioned.directional(
                  textDirection: textDirection,
                  start: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: LiquidGlass(
                    style: LiquidGlassStyle.lensContent(context.colorScheme)
                        .scale(lift),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LensClip extends CustomClipper<Path> {
  const _LensClip(this.rect, this.textDirection);

  final Rect rect;
  final TextDirection textDirection;

  @override
  Path getClip(Size size) => AppShape.full.getOuterPath(
    textDirection == TextDirection.ltr
        ? rect
        : Rect.fromLTRB(
            size.width - rect.right,
            rect.top,
            size.width - rect.left,
            rect.bottom,
          ),
  );

  @override
  bool shouldReclip(_LensClip oldClipper) =>
      rect != oldClipper.rect || textDirection != oldClipper.textDirection;
}

enum _LensPart { both, outside, inside }

class _FloatingBarItem extends StatefulWidget {
  const _FloatingBarItem({
    required this.destination,
    required this.selected,
    required this.index,
    required this.part,
    required this.lens,
    required this.lensWidth,
    required this.jelly,
    required this.parallax,
    required this.lift,
    required this.labelStyle,
    required this.labelHeight,
    required this.labelOverflows,
    required this.onActivate,
  });

  final NavigationDockDestination destination;
  final bool selected;
  final int index;

  /// Only [_LensPart.inside] is drawn bare: it stands over the lens that takes the presses.
  final _LensPart part;
  final _Spring lens;
  final double lensWidth;
  final ValueListenable<double> jelly;
  final ValueListenable<double> parallax;
  final ValueListenable<double> lift;
  final TextStyle? labelStyle;
  final double labelHeight;
  final bool labelOverflows;
  final VoidCallback onActivate;

  @override
  State<_FloatingBarItem> createState() => _FloatingBarItemState();
}

class _FloatingBarItemState extends State<_FloatingBarItem> {
  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onActivate();
        return null;
      },
    ),
  };
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final color = colorScheme.onSurfaceVariant;
    var tint = colorScheme.primary;
    if (widget.part == _LensPart.inside &&
        LiquidGlassScope.qualityOf(context) == LiquidGlassQuality.standard) {
      final brightness = LiquidGlassStyle.lensContent(colorScheme).brightness;
      tint = Color.from(
        alpha: tint.a,
        red: math.min(tint.r * brightness, 1),
        green: math.min(tint.g * brightness, 1),
        blue: math.min(tint.b * brightness, 1),
      );
    }
    final content = _LensTint(
      part: widget.part,
      // With no selection the lens rests at index 0, so tinting would read as selected; skip it.
      active: widget.selected || widget.part == _LensPart.inside,
      lens: widget.lens,
      lensWidth: widget.lensWidth,
      jelly: widget.jelly,
      lift: widget.lift,
      parallax: widget.parallax,
      index: widget.index,
      color: tint,
      textDirection: Directionality.of(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _labelInset),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlyphIcon(
              widget.destination.glyph,
              size: _iconSize,
              color: color,
              fill: 1,
            ),
            const SizedBox(height: _labelGap),
            SizedBox(
              height: widget.labelHeight,
              child: Center(
                child: Text(
                  widget.destination.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: widget.labelStyle?.copyWith(color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.part == _LensPart.inside) {
      return content;
    }
    return FocusableActionDetector(
      actions: _actions,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: Semantics(
        container: true,
        button: true,
        selected: widget.selected,
        label: widget.destination.label,
        excludeSemantics: true,
        onTap: widget.onActivate,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: _focused
                ? colorScheme.onSurface.withValues(alpha: 0.1)
                : Colors.transparent,
            shape: AppShape.full.copyWith(
              side: _focused ? focusRingSide(colorScheme) : BorderSide.none,
            ),
          ),
          child: widget.labelOverflows
              ? Tooltip(message: widget.destination.label, child: content)
              : content,
        ),
      ),
    );
  }
}
