// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'popup.dart';

/// Opens a popup out of the button [targetBuilder] builds; a press opens it at once, as iOS does.
class CommonPopupBox extends StatefulWidget {
  const CommonPopupBox({
    super.key,
    required this.targetBuilder,
    required this.popupBuilder,
    this.placement = PopupPlacement.overAnchorEnd,
  });

  final Widget Function(PopupOpen open) targetBuilder;

  final WidgetBuilder popupBuilder;

  final PopupPlacement placement;

  @override
  State<CommonPopupBox> createState() => _CommonPopupBoxState();
}

class _CommonPopupBoxState extends State<CommonPopupBox> {
  final _sourceKey = GlobalKey();
  final _sourceHidden = ValueNotifier<bool>(false);
  CommonPopupRoute<void>? _route;
  int? _pointer;
  Offset _pressOrigin = Offset.zero;
  bool _pressMoved = false;

  @override
  void dispose() {
    _sourceHidden.dispose();
    super.dispose();
  }

  Rect? _sourceRect() {
    if (!mounted) {
      return null;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize) {
      return null;
    }
    final navigatorBox =
        Navigator.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final origin = renderBox.localToGlobal(Offset.zero, ancestor: navigatorBox);
    return origin & renderBox.size;
  }

  Color _sourceColor() {
    Color? color;
    void visit(Element element) {
      if (color != null) {
        return;
      }
      if (element.widget case final Material material) {
        color = material.type == MaterialType.transparency
            ? Colors.transparent
            : material.color ?? Colors.transparent;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    final resolved = color;
    if (resolved != null && resolved.a > 0) {
      return resolved;
    }
    if (LiquidGlassScope.of(context)) {
      return Colors.transparent;
    }
    final colorScheme = context.colorScheme;
    return SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme);
  }

  void _captureSource(
    CommonPopupRoute<void> route,
    ValueNotifier<ui.Image?> snapshot,
  ) {
    if (!mounted || !route.isActive) {
      return;
    }
    final boundary = _sourceKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      return;
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    snapshot.value = LiquidGlass.withoutPanes(
      () => boundary.toImageSync(pixelRatio: pixelRatio),
    );
    _sourceHidden.value = true;
  }

  bool _targetEnabled() {
    bool? enabled;
    void visit(Element element) {
      if (enabled != null) {
        return;
      }
      if (element.widget case final InkResponse response) {
        enabled = response.onTap != null;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return enabled ?? false;
  }

  bool _canOpen() => _pointer == null && _route == null && _targetEnabled();

  void _handlePress(PointerDownEvent event) {
    _pointer = event.pointer;
    _pressOrigin = event.position;
    _pressMoved = false;
    _releaseFromNavigator(event.pointer);
    _open();
    // A press around the button may hear this down after the box does.
    scheduleMicrotask(() {
      if (mounted) {
        ElasticPress.maybeOf(context)?.release();
      }
    });
  }

  // A navigator cancels the presses it tracks as it navigates (flutter#4770).
  void _releaseFromNavigator(int pointer) {
    final listener = Navigator.maybeOf(context)?.context.findRenderObject();
    if (listener is RenderPointerListener) {
      listener.onPointerCancel?.call(PointerCancelEvent(pointer: pointer));
    }
  }

  // The popup covers the button, so releasing where it went down leaves it open.
  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    final slop = computeHitSlop(
      event.kind,
      MediaQuery.maybeGestureSettingsOf(context),
    );
    _pressMoved =
        _pressMoved || (event.position - _pressOrigin).distance > slop;
    if (_pressMoved) {
      _route?._press.onMove?.call(event.position);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    if (_pressMoved) {
      _route?._press.onRelease?.call(event.position);
    }
  }

  void _handlePressCancel() {
    if (_pointer == null) {
      return;
    }
    _pointer = null;
    _route?._press.onCancel?.call();
  }

  void _open() {
    if (_route != null) {
      return;
    }
    final snapshot = ValueNotifier<ui.Image?>(null);
    final route = _route = CommonPopupRoute<void>(
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (context) => widget.popupBuilder(context),
      anchorOf: _sourceRect,
      placement: widget.placement,
      elevated: ElevatedSurfaceTheme.isIn(context),
      sourceColor: _sourceColor(),
      sourceImage: snapshot,
    );
    Navigator.of(context).push(route);
    void reveal() {
      if (mounted) {
        _sourceHidden.value = false;
      }
    }

    route.animation!.addStatusListener((status) {
      if (status.isDismissed) {
        reveal();
      }
    });
    route.completed.whenComplete(() {
      if (identical(_route, route)) {
        _route = null;
      }
      reveal();
      snapshot.value?.dispose();
      snapshot.dispose();
    });
    // The control repaints its ink when tapped, so capture after that frame.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _captureSource(route, snapshot),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      excludeFromSemantics: true,
      gestures: {
        _PopupPressRecognizer:
            GestureRecognizerFactoryWithHandlers<_PopupPressRecognizer>(
              () => _PopupPressRecognizer(debugOwner: this),
              (recognizer) => recognizer
                ..delay = Scrollable.maybeOf(context) == null
                    ? Duration.zero
                    : kPressTimeout
                ..canOpen = _canOpen
                ..onPress = _handlePress
                ..onMove = _handlePointerMove
                ..onUp = _handlePointerUp
                ..onCancel = _handlePressCancel,
            ),
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: _sourceHidden,
        builder: (_, hidden, child) =>
            Opacity(opacity: hidden ? 0 : 1, child: child),
        child: RepaintBoundary(
          key: _sourceKey,
          child: widget.targetBuilder(_open),
        ),
      ),
    );
  }
}

const _valueBlur = 4.0;

class PopupValueText extends StatelessWidget {
  const PopupValueText(
    this.text, {
    super.key,
    this.alignment = AlignmentDirectional.center,
  });

  final String text;
  final AlignmentGeometry alignment;

  static Widget _transition(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, child) {
          final sigma = _valueBlur * (1 - animation.value);
          return ImageFiltered(
            enabled: sigma > 0,
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: child,
          );
        },
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = context.motionDuration(commonDuration);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: alignment,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: const Interval(0.3, 1, curve: Curves.easeOut),
        switchOutCurve: const Interval(0.6, 1, curve: Curves.easeIn),
        transitionBuilder: _transition,
        // The old value takes no room, so the button sizes to the new one as AnimatedSize eases it.
        layoutBuilder: (current, previous) => Stack(
          alignment: alignment,
          clipBehavior: Clip.none,
          children: [
            for (final child in previous)
              SizedOverflowBox(
                size: Size.zero,
                alignment: alignment,
                child: child,
              ),
            ?current,
          ],
        ),
        child: Text(
          text,
          key: ValueKey(text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Opens a popup on its button pointer down and carries the press in; a scroll view waits [delay].
class _PopupPressRecognizer extends OneSequenceGestureRecognizer {
  _PopupPressRecognizer({super.debugOwner});

  Duration delay = Duration.zero;
  bool Function()? canOpen;
  ValueSetter<PointerDownEvent>? onPress;
  ValueSetter<PointerMoveEvent>? onMove;
  ValueSetter<PointerUpEvent>? onUp;
  VoidCallback? onCancel;

  PointerDownEvent? _down;
  Timer? _timer;
  bool _pressed = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _down == null &&
      event.buttons == kPrimaryButton &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!(canOpen?.call() ?? false)) {
      return;
    }
    _down = event;
    _pressed = false;
    startTrackingPointer(event.pointer, event.transform);
    if (delay == Duration.zero) {
      _press();
    } else {
      _timer = Timer(delay, _press);
    }
  }

  void _press() {
    _timer?.cancel();
    _timer = null;
    final down = _down;
    if (down == null || _pressed) {
      return;
    }
    _pressed = true;
    resolve(GestureDisposition.accepted);
    onPress?.call(down);
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _down;
    if (down == null) {
      return;
    }
    if (event is PointerMoveEvent) {
      if (_pressed) {
        onMove?.call(event);
      } else if ((event.position - down.position).distance >
          computeHitSlop(event.kind, gestureSettings)) {
        resolve(GestureDisposition.rejected);
        _reset(event.pointer);
      }
    } else if (event is PointerUpEvent) {
      _press();
      onUp?.call(event);
      _reset(event.pointer);
    } else if (event is PointerCancelEvent) {
      if (_pressed) {
        onCancel?.call();
      } else {
        resolve(GestureDisposition.rejected);
      }
      _reset(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    final pressed = _pressed;
    _reset(pointer);
    if (pressed) {
      onCancel?.call();
    }
  }

  void _reset(int pointer) {
    _timer?.cancel();
    _timer = null;
    _down = null;
    _pressed = false;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  String get debugDescription => 'popup press';
}

class CommonPopupMenuItem {
  const CommonPopupMenuItem({
    required this.label,
    this.subtitle,
    this.glyph,
    this.onPressed,
    this.danger = false,
    this.checked,
    this.section,
    this.subItems = const [],
  });

  final String label;
  final String? subtitle;
  final Glyph? glyph;
  final VoidCallback? onPressed;
  final bool danger;
  final bool? checked;

  /// Sets this item and those after it apart from the items above, as an
  /// inline section of an iOS menu does.
  final CommonPopupMenuSection? section;
  final List<CommonPopupMenuItem> subItems;
}

class CommonPopupMenuSection {
  const CommonPopupMenuSection({this.title});

  final String? title;
}

const _menuMinWidth = 160.0;
const _menuMaxWidth = 280.0;
const _defaultMaxVisibleItems = 7;
