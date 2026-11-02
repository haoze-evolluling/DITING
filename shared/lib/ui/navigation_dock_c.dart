// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'navigation_dock.dart';

/// A floating pill of destinations with a lens that springs between them, after iOS's tab bar.
class FloatingNavigationBar extends StatefulWidget {
  const FloatingNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<NavigationDockDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<FloatingNavigationBar> createState() => _FloatingNavigationBarState();
}

class _FloatingNavigationBarState extends State<FloatingNavigationBar>
    with TickerProviderStateMixin {
  late final _Spring _lens = _Spring(this, _selectedIndex.toDouble());
  late final _Spring _lift = _Spring(this, 0);
  late final _Spring _hover = _Spring(this, 0);
  late final _Spring _hoverShow = _Spring(this, 0);
  late final _Spring _swell = _Spring(this, 0);
  late final _Spring _stretch = _Spring(this, 0);
  late final _Spring _jelly = _Spring(this, 0, rest: _jellyRest);
  late final _Spring _glow = _Spring(this, 0);
  late final _Spring _glowSpread = _Spring(this, 0);
  final ValueNotifier<LiquidGlassGlow> _touchGlow = ValueNotifier(
    LiquidGlassGlow.none,
  );
  Offset _glowAt = Offset.zero;
  late final Listenable _barMotion = Listenable.merge([_swell, _stretch]);
  late final Listenable _motion = Listenable.merge([_lens, _lift, _jelly]);
  late final Listenable _hoverMotion = Listenable.merge([_hover, _hoverShow]);
  final List<_Spring> _parallax = [];
  bool _lifted = false;
  int? _pointer;
  int? _pressedIndex;
  double _pressX = 0;
  bool _dragging = false;
  bool _dropping = false;
  VelocityTracker? _tracker;
  Offset? _cursor;
  final ValueNotifier<double?> _hoverAt = ValueNotifier(null);

  int get _lastIndex => math.max(0, widget.destinations.length - 1);

  int get _selectedIndex => widget.selectedIndex.clamp(0, _lastIndex);

  /// The current page is not in the dock. `AppShell` passes -1: nothing lights up, and a tap
  /// commits.
  bool get _hasSelection =>
      widget.destinations.isNotEmpty && widget.selectedIndex >= 0;

  ({double pitch, double lens, double inset}) get _layout => _dockLayout(
    context.size!.width - _barPadding * 2,
    widget.destinations.length,
  );

  @override
  void initState() {
    super.initState();
    _lens
      ..addListener(_wobble)
      ..addListener(_dropLift);
    _lift
      ..addListener(_dropLift)
      ..addListener(_noteLift);
    _glow.addListener(_shine);
    _glowSpread.addListener(_shine);
    _hoverAt.addListener(_leanContent);
    _syncParallax();
  }

  @override
  void didUpdateWidget(covariant FloatingNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncParallax();
    _leanContent();
    final rest = _lensRest;
    if (_pressedIndex == null && _lens.target != rest) {
      _lens.springTo(rest, _travelSpring);
    }
  }

  @override
  void dispose() {
    for (final parallax in _parallax) {
      parallax.dispose();
    }
    _lens.dispose();
    _lift.dispose();
    _hover.dispose();
    _hoverShow.dispose();
    _swell.dispose();
    _stretch.dispose();
    _jelly.dispose();
    _glow.dispose();
    _glowSpread.dispose();
    _touchGlow.dispose();
    _hoverAt.dispose();
    super.dispose();
  }

  void _wobble() {
    final velocity = _lens.velocity;
    final braking = math.max(0.0, -_lens.acceleration * velocity.sign);
    final target =
        _jellyStretch * _saturate(velocity.abs() / _jellySpeed) -
        _jellySquash * _saturate(braking / _jellyBrake);
    if (target != _jelly.target) {
      _jelly.springTo(target, _jellySpring);
    }
  }

  // UIKit lights the bar from the finger, washing over the rest, and spreads it as it fades.
  void _shine() {
    final glow = _glow.value;
    _touchGlow.value = LiquidGlassGlow(
      center: _glowAt,
      reach: _glowReach * (1 + _glowGrowth * _glowSpread.value),
      strength: _glowPeak * glow * glow,
      wash: _glowWash,
    );
  }

  void _syncParallax() {
    final count = widget.destinations.length;
    while (_parallax.length > count) {
      _parallax.removeLast().dispose();
    }
    while (_parallax.length < count) {
      _parallax.add(_Spring(this, 0));
    }
  }

  void _leanContent() {
    final hoverAt = _hoverAt.value;
    for (final (index, parallax) in _parallax.indexed) {
      final offset = hoverAt == null ? 0.0 : hoverAt - index;
      final target = offset.abs() > 0.5
          ? 0.0
          : offset * _hoverMagnet * _hoverParallax;
      if (target != parallax.target) {
        parallax.springTo(target, _hoverSpring);
      }
    }
  }

  void _noteLift() {
    final lifted = _lift.value > 0;
    if (lifted != _lifted) {
      setState(() => _lifted = lifted);
    }
  }

  // UIKit keeps the lens lifted until it has risen all the way and arrived.
  void _dropLift() {
    if (!_dropping || _pointer != null || _lift.value < _liftSnap) {
      return;
    }
    if ((_lens.target - _lens.value).abs() > _liftRelease) {
      return;
    }
    _dropping = false;
    _lift.springTo(0, _liftSpring);
  }

  double _positionAt(Offset localPosition) {
    final width = context.size!.width;
    final dx = Directionality.of(context) == TextDirection.ltr
        ? localPosition.dx
        : width - localPosition.dx;
    final layout = _layout;
    final position = (dx - _barPadding - layout.inset) / layout.pitch - 0.5;
    if (position < 0) {
      return _rubberBand(position, _overdrag);
    }
    if (position > _lastIndex) {
      return _lastIndex + _rubberBand(position - _lastIndex, _overdrag);
    }
    return position;
  }

  int _indexAt(double position) => position.round().clamp(0, _lastIndex);

  double _leanAt(double position) {
    final index = _indexAt(position);
    return index + (position - index) * _hoverMagnet;
  }

  double get _lensRest {
    final hoverAt = _hoverAt.value;
    if (hoverAt == null || _indexAt(hoverAt) != _selectedIndex) {
      return _selectedIndex.toDouble();
    }
    return _leanAt(hoverAt);
  }

  // A lens headed to a just-tapped destination is left for didUpdateWidget.
  void _leanLens() {
    if (_pressedIndex != null || _indexAt(_lens.target) != _selectedIndex) {
      return;
    }
    final rest = _lensRest;
    if (_lens.target != rest) {
      _lens.springTo(rest, _hoverSpring);
    }
  }

  void _showHover() {
    final cursor = _cursor;
    if (cursor == null || _pointer != null || widget.destinations.isEmpty) {
      return;
    }
    final position = _positionAt(cursor);
    final target = _leanAt(position);
    _hoverAt.value = position;
    if (_hoverShow.target == 0 && _hoverShow.value == 0) {
      _hover.jumpTo(target);
    } else {
      _hover.springTo(target, _hoverSpring);
    }
    _hoverShow.springTo(1, _fadeSpring);
    _leanLens();
  }

  void _settleSwell(SpringDescription spring) {
    final target = _cursor == null ? 0.0 : _hoverSwell;
    if (_pointer == null && _swell.target != target) {
      _swell.springTo(target, spring);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final labelStyle = AppTextStyle.custom(
      context,
      size: _labelSize,
      leading: _labelLeading,
      weight: FontWeight.w500,
    );
    final labels = [
      for (final destination in widget.destinations)
        _measureLabel(context, destination.label, labelStyle),
    ];
    final widest = labels.fold(
      0.0,
      (width, label) => math.max(width, label.width),
    );
    final lineHeight = labels.fold(
      0.0,
      (height, label) => math.max(height, label.height),
    );
    final glass = LiquidGlassScope.of(context);
    final ultra =
        LiquidGlassScope.qualityOf(context) == LiquidGlassQuality.ultra;
    final bar = _DockSurface(
      glass: glass,
      style: LiquidGlassStyle.pill(colorScheme),
      shadows: ultra ? dockGlassShadows(colorScheme) : const [],
      glow: _touchGlow,
      child: Material(
        color: glass
            ? Colors.transparent
            : SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme),
        shape: AppShape.full,
        // Raw pointers rather than recognizers: a tap waiting on the arena lifts the lens late.
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerEnd,
          onPointerCancel: _handlePointerEnd,
          child: MouseRegion(
            onHover: _handleHover,
            onExit: _handleExit,
            child: Padding(
              padding: const EdgeInsets.all(_barPadding),
              // Above the LayoutBuilder: rebuilding under one relays it out over the whole dock.
              child: RepaintBoundary(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final layout = _dockLayout(
                      constraints.maxWidth,
                      widget.destinations.length,
                    );
                    final room = layout.pitch - _labelInset * 2;
                    final labelScale = widest <= room
                        ? 1.0
                        : math.max(room / widest, _minLabelSize / _labelSize);
                    Rect lensRect() => _lensRect(
                      position: _lens.value,
                      stretch: _jelly.value,
                      pitch: layout.pitch,
                      width: layout.lens,
                      height: constraints.maxHeight,
                      lift: _lift.value,
                    ).shift(Offset(layout.inset, 0));
                    Widget items(_LensPart part) => Padding(
                      padding: EdgeInsets.symmetric(horizontal: layout.inset),
                      child: Row(
                        children: [
                          for (final (index, destination)
                              in widget.destinations.indexed)
                            Expanded(
                              child: _FloatingBarItem(
                                destination: destination,
                                selected:
                                    _hasSelection && index == _selectedIndex,
                                index: index,
                                part: part,
                                lens: _lens,
                                lensWidth: layout.lens,
                                jelly: _jelly,
                                parallax: _parallax[index],
                                lift: _lift,
                                labelStyle: labelStyle.copyWith(
                                  fontSize: _labelSize * labelScale,
                                ),
                                labelHeight: lineHeight,
                                labelOverflows:
                                    labels[index].width * labelScale > room,
                                onActivate: () => widget.onSelected(index),
                              ),
                            ),
                        ],
                      ),
                    );
                    final lensed = glass && _lifted && _hasSelection;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (_hasSelection)
                          AnimatedBuilder(
                            animation: _motion,
                            builder: (_, _) => _Lens(
                              rect: lensRect(),
                              lift: _lift.value,
                              glass: glass,
                            ),
                          ),
                        if (_hasSelection)
                          AnimatedBuilder(
                            animation: _hoverMotion,
                            builder: (_, _) => _HoverHighlight(
                              start:
                                  layout.inset +
                                  (_hover.value + 0.5) * layout.pitch -
                                  layout.lens / 2,
                              width: layout.lens,
                              opacity: _hoverShow.value,
                            ),
                          ),
                        if (glass && _hasSelection)
                          AnimatedBuilder(
                            animation: _motion,
                            builder: (_, _) =>
                                _GlassLens(rect: lensRect(), lift: _lift.value),
                          ),
                        items(lensed ? _LensPart.outside : _LensPart.both),
                        if (lensed)
                          AnimatedBuilder(
                            animation: _motion,
                            builder: (_, child) => _LensContent(
                              rect: lensRect(),
                              lift: _lift.value,
                              warp: ultra,
                              child: child!,
                            ),
                            child: items(_LensPart.inside),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _barMotion,
      builder: (_, child) => _PressTransform(
        lift: _swell.value,
        pull: Offset(_stretch.value, 0),
        child: child,
      ),
      child: bar,
    );
  }
}
