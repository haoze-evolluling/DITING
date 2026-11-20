// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'navigation_dock.dart';

class _Spring extends ChangeNotifier implements ValueListenable<double> {
  _Spring(TickerProvider vsync, this._value, {this.rest = 1e-3}) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  double _value;

  final double rest;
  double _target = 0;
  SpringSimulation? _simulation;
  SpringDescription? _spring;
  double _now = 0;
  double _start = 0;

  @override
  double get value => _value;

  double get target => _simulation == null ? _value : _target;

  double get velocity => _simulation?.dx(_now - _start) ?? 0;

  double get acceleration {
    final spring = _spring;
    if (_simulation == null || spring == null) {
      return 0;
    }
    return (spring.stiffness * (_target - _value) - spring.damping * velocity) /
        spring.mass;
  }

  void springTo(double target, SpringDescription spring) {
    _simulation = SpringSimulation(
      spring,
      _value,
      target,
      velocity,
      tolerance: Tolerance(
        distance: rest,
        velocity: rest * math.sqrt(spring.stiffness / spring.mass),
      ),
    );
    _spring = spring;
    _target = target;
    if (_ticker.isActive) {
      _start = _now;
      return;
    }
    _now = _start = 0;
    _ticker.start();
  }

  void jumpTo(double value) {
    _simulation = null;
    _ticker.stop();
    _value = value;
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final simulation = _simulation!;
    final time = _now - _start;
    if (simulation.isDone(time)) {
      _value = _target;
      _simulation = null;
      _ticker.stop();
    } else {
      _value = simulation.x(time);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

List<BoxShadow> dockShadows(ColorScheme colorScheme) {
  final strength = colorScheme.brightness == Brightness.dark ? 3.0 : 1.0;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.08 * strength),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.04 * strength),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];
}

List<BoxShadow> dockGlassShadows(ColorScheme colorScheme) => [
  BoxShadow(
    color: colorScheme.shadow.withValues(alpha: 0.013),
    blurRadius: 3.8,
    offset: const Offset(0, 6.5),
  ),
];

class _DockSurface extends StatelessWidget {
  const _DockSurface({
    required this.glass,
    required this.style,
    required this.shadows,
    required this.glow,
    required this.child,
  });

  final bool glass;
  final LiquidGlassStyle style;
  final List<BoxShadow> shadows;
  final ValueListenable<LiquidGlassGlow> glow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    if (glass) {
      return ValueListenableBuilder(
        valueListenable: glow,
        builder: (_, glow, child) => LiquidGlass(
          style: style,
          shadows: shadows,
          glow: glow,
          child: child,
        ),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: _dockShape,
        shadows: dockShadows(colorScheme),
      ),
      child: child,
    );
  }
}

({double width, double height}) _measureLabel(
  BuildContext context,
  String label,
  TextStyle? style,
) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  final size = (width: painter.width, height: painter.height);
  painter.dispose();
  return size;
}

class NavigationDockDestination {
  const NavigationDockDestination({required this.glyph, required this.label});

  final Glyph glyph;
  final String label;
}

class NavigationDock extends StatelessWidget {
  const NavigationDock({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<NavigationDockDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static double heightOf(BuildContext context) {
    final labelSize = AppTextRole.dockLabel.sizeOf(context);
    return _barHeight +
        MediaQuery.textScalerOf(context).scale(labelSize) -
        labelSize;
  }

  static double _bottomMarginOf(BuildContext context) =>
      math.max(_edgeMargin, MediaQuery.paddingOf(context).bottom);

  static double insetOf(BuildContext context) =>
      heightOf(context) + _bottomMarginOf(context) + dockContentGap;

  @override
  Widget build(BuildContext context) {
    final height = heightOf(context);
    final dock = Padding(
      padding: EdgeInsets.fromLTRB(
        _edgeMargin,
        _shadowRoom,
        _edgeMargin,
        _bottomMarginOf(context),
      ),
      child: _HitSlop(
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: _HitSlop(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: destinations.length >= _fullWidthCount
                          ? double.infinity
                          : destinations.length * _maxItemExtent +
                                _barPadding * 4,
                    ),
                    child: FloatingNavigationBar(
                      destinations: destinations,
                      selectedIndex: selectedIndex,
                      onSelected: onSelected,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      width: double.infinity,
      height: _shadowRoom + height + _bottomMarginOf(context),
      child: RepaintBoundary(child: LayoutBuilder(builder: (_, _) => dock)),
    );
  }
}
