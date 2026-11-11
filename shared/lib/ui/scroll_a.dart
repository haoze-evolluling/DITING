// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'scroll.dart';

class _AppScrollbarState extends RawScrollbarState<_AppScrollbar> {
  late final AnimationController _emphasis;
  late final CurvedAnimation _emphasisCurve;
  late final AnimationController _presence;
  ValueListenable<bool>? _sheetOpen;
  var _hidden = false;
  late ColorScheme _colorScheme;
  late TargetPlatform _platform;
  var _hovered = false;
  var _dragging = false;
  Offset? _scrubOrigin;
  Offset? _scrubLast;
  Offset? _scrubPosition;
  var _scrubRate = 1.0;
  ScrubbableScrollPosition? _scrubbed;

  @override
  void initState() {
    super.initState();
    _emphasis = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    )..addListener(updateScrollbarPainter);
    _emphasisCurve = CurvedAnimation(parent: _emphasis, curve: Curves.easeOut);
    _presence = AnimationController(
      vsync: this,
      duration: widget.fadeDuration,
      value: 1,
    )..addListener(updateScrollbarPainter);
  }

  @override
  void didChangeDependencies() {
    final theme = Theme.of(context);
    _colorScheme = theme.colorScheme;
    _platform = theme.platform;
    super.didChangeDependencies();
    _watchSheet();
  }

  @override
  void didUpdateWidget(_AppScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _watchSheet();
  }

  @override
  void dispose() {
    _endScrub();
    _sheetOpen?.removeListener(_syncSheet);
    _presence.dispose();
    _emphasisCurve.dispose();
    _emphasis.dispose();
    super.dispose();
  }

  @override
  bool get enableGestures => super.enableGestures && !_hidden;

  // A thumb already held keeps its drag, or its scrub would never end.
  bool get _sheetHides => !_dragging && !(_sheetOpen?.value ?? true);

  void _watchSheet() {
    final controller =
        widget.controller ?? PrimaryScrollController.maybeOf(context);
    final sheetOpen = controller is SheetScrollController
        ? controller.sheetOpen
        : null;
    if (sheetOpen == _sheetOpen) {
      return;
    }
    _sheetOpen?.removeListener(_syncSheet);
    _sheetOpen = sheetOpen?..addListener(_syncSheet);
    _hidden = _sheetHides;
    _presence.value = _hidden ? 0 : 1;
  }

  void _syncSheet() {
    final hidden = _sheetHides;
    if (hidden == _hidden) {
      return;
    }
    setState(() => _hidden = hidden);
    if (hidden) {
      _presence.reverse();
    } else {
      _presence.forward();
    }
  }

  void _beginScrub() {
    final controller =
        widget.controller ?? PrimaryScrollController.maybeOf(context);
    if (controller == null || controller.positions.length != 1) {
      return;
    }
    final position = controller.position;
    if (position is ScrubbableScrollPosition) {
      _scrubbed = position..isScrubbing = true;
    }
  }

  void _endScrub() {
    _scrubbed?.isScrubbing = false;
    _scrubbed = null;
  }

  void _syncEmphasis() {
    if (_hovered || _dragging) {
      _emphasis.forward();
    } else {
      _emphasis.reverse();
    }
  }

  double _scrubRateFor(double sidewaysDistance) {
    if (!isTouchPlatform(_platform)) {
      return 1.0;
    }
    final band = (sidewaysDistance / _scrubBandWidth).floor();
    return _scrubRates[band.clamp(0, _scrubRates.length - 1)];
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    final t = _emphasisCurve.value;
    final onSurface = _colorScheme.onSurface;
    final isDark = _colorScheme.brightness == Brightness.dark;
    final color = Color.lerp(
      onSurface.withValues(alpha: isDark ? 0.35 : 0.25),
      onSurface.withValues(alpha: isDark ? 0.65 : 0.5),
      t,
    )!;
    scrollbarPainter
      ..color = color.withValues(alpha: color.a * _presence.value)
      ..thickness = _restThickness + (_activeThickness - _restThickness) * t;
  }

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    if (getScrollbarDirection() == null) {
      return;
    }
    _beginScrub();
    _dragging = true;
    _scrubOrigin = localPosition;
    _scrubLast = localPosition;
    _scrubPosition = localPosition;
    _scrubRate = 1.0;
    _syncEmphasis();
    if (isTouchPlatform(_platform)) {
      HapticFeedback.selectionClick();
    }
    widget.onScrub?.call(_scrubRate);
  }

  // The thumb maps to an absolute offset; feed the base class the scaled delta only.
  @override
  void handleThumbPressUpdate(Offset localPosition) {
    final origin = _scrubOrigin;
    final last = _scrubLast;
    final position = _scrubPosition;
    final direction = getScrollbarDirection();
    if (origin == null || last == null || position == null) {
      super.handleThumbPressUpdate(localPosition);
      return;
    }
    final Offset next;
    final double rate;
    switch (direction) {
      case Axis.vertical:
        rate = _scrubRateFor((localPosition.dx - origin.dx).abs());
        next = Offset(
          localPosition.dx,
          position.dy + (localPosition.dy - last.dy) * rate,
        );
      case Axis.horizontal:
        rate = _scrubRateFor((localPosition.dy - origin.dy).abs());
        next = Offset(
          position.dx + (localPosition.dx - last.dx) * rate,
          localPosition.dy,
        );
      case null:
        super.handleThumbPressUpdate(localPosition);
        return;
    }
    _scrubLast = localPosition;
    _scrubPosition = next;
    if (rate != _scrubRate) {
      _scrubRate = rate;
      widget.onScrub?.call(rate);
    }
    super.handleThumbPressUpdate(next);
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    final position = _scrubPosition ?? localPosition;
    final slowed = _scrubRate < 1;
    _dragging = false;
    _scrubOrigin = null;
    _scrubLast = null;
    _scrubPosition = null;
    _scrubRate = 1.0;
    _syncEmphasis();
    // A fling would throw away the precision the slowed scrub just bought.
    super.handleThumbPressEnd(position, slowed ? Velocity.zero : velocity);
    _endScrub();
    widget.onScrub?.call(null);
    _syncSheet();
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    final hovered = isPointerOverScrollbar(
      event.position,
      event.kind,
      forHover: true,
    );
    if (hovered != _hovered) {
      _hovered = hovered;
      _syncEmphasis();
    }
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    if (_hovered) {
      _hovered = false;
      _syncEmphasis();
    }
  }
}

class FloatingScrollbar extends StatefulWidget {
  final ScrollController controller;
  final String Function(double fraction) hintBuilder;
  final bool thumbVisibility;
  final Widget child;

  const FloatingScrollbar({
    super.key,
    required this.controller,
    required this.hintBuilder,
    this.thumbVisibility = false,
    required this.child,
  });

  @override
  State<FloatingScrollbar> createState() => _FloatingScrollbarState();
}

class _FloatingScrollbarState extends State<FloatingScrollbar> {
  var _hintVisible = false;
  var _hintMounted = false;
  double? _scrubRate;
  var _pillHeight = 0.0;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Lazy lists refine maxScrollExtent during layout without a notification.
    widget.controller.addListener(_syncPosition);
  }

  @override
  void didUpdateWidget(FloatingScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncPosition);
      widget.controller.addListener(_syncPosition);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_syncPosition);
    super.dispose();
  }

  void _syncPosition() {
    if (_hintMounted && mounted) {
      setState(() {});
    }
  }

  void _handleScrub(double? rate) {
    _hideTimer?.cancel();
    if (rate != null) {
      final appearing = !_hintMounted;
      setState(() {
        _scrubRate = rate;
        _hintVisible = !appearing;
        _hintMounted = true;
      });
      if (appearing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _hintMounted) {
            setState(() => _hintVisible = true);
          }
        });
      }
      return;
    }
    setState(() => _scrubRate = null);
    // Lingers so letting go and grabbing again does not blink the hint.
    _hideTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _hintVisible = false);
      }
    });
  }

  double _thumbCenter(
    ScrollMetrics metrics,
    double height,
    EdgeInsets padding,
  ) {
    final track = height - padding.vertical;
    final scrollableExtent = metrics.maxScrollExtent - metrics.minScrollExtent;
    final fraction = scrollableExtent > 0
        ? ((metrics.pixels - metrics.minScrollExtent) / scrollableExtent).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final totalContent =
        metrics.maxScrollExtent + metrics.viewportDimension - padding.vertical;
    final fractionVisible = totalContent > 0
        ? ((metrics.extentInside - padding.vertical) / totalContent).clamp(
            0.0,
            1.0,
          )
        : 1.0;
    // Reversed lists place the thumb at (1 - fraction).
    final thumbExtent = max(
      _minThumbLength,
      track * fractionVisible,
    ).clamp(0.0, track);
    final thumbFraction = axisDirectionIsReversed(metrics.axisDirection)
        ? 1 - fraction
        : fraction;
    return padding.top +
        thumbFraction * (track - thumbExtent) +
        thumbExtent / 2;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = BottomInsetScope.of(context);
    final behavior = ScrollConfiguration.of(context);
    final barPadding = behavior is BaseScrollBehavior
        ? behavior.scrollbarPadding
        : EdgeInsets.zero;
    // A finger on the thumb covers the bar's edge, so the hint keeps clear.
    final hintGap = isTouchPlatform(Theme.of(context).platform) ? 40.0 : 20.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        String? label;
        var top = 0.0;
        if (_hintMounted && widget.controller.hasClients) {
          final metrics = widget.controller.position;
          if (metrics.maxScrollExtent > metrics.minScrollExtent) {
            final scrollableExtent =
                metrics.maxScrollExtent - metrics.minScrollExtent;
            final fraction =
                ((metrics.pixels - metrics.minScrollExtent) / scrollableExtent)
                    .clamp(0.0, 1.0);
            // Continuous clamp keeps the pill clear of the bottom inset.
            final half = _pillHeight / 2;
            final limit =
                (constraints.maxHeight - bottomInset - _bottomInsetGap).clamp(
                  0.0,
                  double.infinity,
                );
            top = _thumbCenter(
              metrics,
              constraints.maxHeight,
              MediaQuery.paddingOf(context) +
                  barPadding +
                  EdgeInsets.only(top: _barClearance(context)),
            ).clamp(half, max(half, limit - half));
            label = widget.hintBuilder(fraction);
          }
        }
        return Stack(
          children: [
            CommonScrollBar(
              controller: widget.controller,
              thumbVisibility: widget.thumbVisibility,
              padding: barPadding,
              onScrub: _handleScrub,
              child: widget.child,
            ),
            // Outlives the label, so the fade-out still ends and unmounts it.
            if (_hintMounted)
              Positioned(
                right: hintGap,
                top: top,
                child: FractionalTranslation(
                  translation: const Offset(0, -0.5),
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _hintVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      onEnd: () {
                        if (!_hintVisible) {
                          setState(() => _hintMounted = false);
                        }
                      },
                      child: label == null
                          ? const SizedBox.shrink()
                          : _MeasureSize(
                              onChanged: (size) {
                                if (mounted && size.height != _pillHeight) {
                                  setState(() => _pillHeight = size.height);
                                }
                              },
                              child: _ScrollbarHintPill(
                                label: label,
                                scrubRate: _scrubRate,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
