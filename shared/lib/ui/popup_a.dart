// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'popup.dart';

// Soft and wide like HyperOS menus rather than a Material elevation.
List<BoxShadow> _cardShadows(ColorScheme colorScheme, [double depth = 1]) {
  final strength = colorScheme.brightness == Brightness.dark ? 3.0 : 1.0;
  final alpha = strength * depth;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.05 * alpha),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.04 * alpha),
      blurRadius: 30,
      offset: const Offset(0, 4),
    ),
  ];
}

const _maxContentBlur = 8.0;

const _overshootPerLongestSide = 0.1;

const _openDuration = Duration(milliseconds: 450);

const _dismissDuration = Duration(milliseconds: 500);

const _shrinkDuration = Duration(milliseconds: 200);

/// How far a popup with no control to return into shrinks toward its anchor as it fades.
const _dismissScale = 0.8;

double _secondsOf(Duration duration) =>
    duration.inMicroseconds / Duration.microsecondsPerSecond;

final _openSeconds = _secondsOf(_openDuration);

final _dismissSeconds = _secondsOf(_dismissDuration);

// iOS 27 returns a menu into its button as one drop of glass: the platter dips
// away, then shrinks into the button, which re-forms out of a droplet and rises
// past its place. iOS lays a menu over its button; one here opens beside it, so
// it dips half as far, or the two would part.
final _droplet = SpringSimulation(dropletSpring, 0, 1, 0);
const _dropletBlend = 28.0;
const _dropletContentOut = 0.1;
const _dropletGlyphIn = 0.47;
const _dropletGlyphCurve = Cubic(0.25, 0.1, 0.25, 1);

// Inside the button by then, the platter stops swelling it and the glass eases
// back to the button's, so the last frame is the button itself.
const _dropletAbsorbed = Interval(0.6, 0.9, curve: Curves.easeInOut);

// As measured on iOS 27: one spring opens the menu, a later one squares off its
// capsule corners.
final _open = SpringSimulation(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 400, ratio: 0.754),
  0,
  1,
  0,
);
final _corners = SpringSimulation(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 324, ratio: 0.75),
  1,
  0,
  0,
);
const _cornersDelay = 0.07;
const _cornersReachPerWidth = 0.48;
const _openContentBlur = 4.0;
const _openBlurBump = 1.9;
const _unseenBlur = 0.1;
const _platterInControl = 0.41;
const _dropletShare = 0.25;
const _rimDepth = 8.0;
const _glyphUnderAt = 0.25;

const _dwellDuration = Duration(milliseconds: 400);

final _unfoldSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 420),
  bounce: 0.15,
);

final _foldSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 340),
);

class CommonPopupRoute<T> extends PopupRoute<T> {
  CommonPopupRoute({
    required this.builder,
    required this.anchorOf,
    required this.barrierLabel,
    this.placement = PopupPlacement.overAnchorEnd,
    this.elevated = false,
    this.sourceColor = Colors.transparent,
    this.sourceImage,
    this.modal = true,
    this.avoid,
  }) : super(requestFocus: modal ? null : false);

  final WidgetBuilder builder;

  final PopupAnchorResolver anchorOf;
  final PopupPlacement placement;

  /// Whether the popup opens from a sheet's [ElevatedSurfaceTheme], below its navigator.
  final bool elevated;

  final Color sourceColor;

  /// A snapshot of the source control, drawn inside the platter while the control is hidden.
  final ValueListenable<ui.Image?>? sourceImage;

  final bool modal;

  final Rect? avoid;

  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => _openDuration;

  @override
  Duration get reverseTransitionDuration =>
      sourceImage == null ? _shrinkDuration : _dismissDuration;

  // A controller reverses over the share of its duration it had run, so a
  // popup closed while opening would rush the return its morph times in full.
  @override
  bool didPop(T? result) {
    final controller = this.controller!;
    controller.reverseDuration =
        reverseTransitionDuration * (1 / math.max(controller.value, 1e-3));
    return super.didPop(result);
  }

  final _unfolded = ValueNotifier<bool>(false);

  /// Whether the platter shows rather than the cards, which on glass stand
  /// bare meanwhile so that one pane, the platter's, bends what lies behind.
  final _platter = ValueNotifier<bool>(true);

  final _pin = _PopupPin();

  final _press = _CarriedPress();

  final _surface = _PopupSurface();

  @override
  void install() {
    super.install();
    animation!
      ..addListener(_updatePlatter)
      ..addStatusListener(_handleStatusChanged);
    _unfolded.addListener(_updatePlatter);
  }

  void _handleStatusChanged(AnimationStatus status) => _updatePlatter();

  void _updatePlatter() {
    final animation = this.animation!;
    // A popup with a control to return into does so on the platter; one
    // without dissolves as it stood when it began to close.
    if (animation.status == AnimationStatus.reverse) {
      if (sourceImage != null) {
        _platter.value = true;
      }
      return;
    }
    _platter.value = !animation.isCompleted && !_unfolded.value;
  }

  @override
  void dispose() {
    animation
      ?..removeListener(_updatePlatter)
      ..removeStatusListener(_handleStatusChanged);
    _unfolded.dispose();
    _platter.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    if (isCurrent) {
      navigator?.pop();
    }
  }

  /// A popup that returns into its control runs a picked item once landed, so nothing rebuilds.
  void _runPicked(VoidCallback action) {
    if (sourceImage == null) {
      action();
      return;
    }
    unawaited(completed.whenComplete(action));
  }

  @override
  Widget buildModalBarrier() {
    return modal ? super.buildModalBarrier() : const SizedBox.shrink();
  }

  Widget _buildDismissLayer() {
    if (modal) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: _handleDismiss,
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _handleDismiss(),
      onPointerPanZoomStart: (_) => _handleDismiss(),
      onPointerSignal: (_) => _handleDismiss(),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return SurfaceScope(
      level: SurfaceLevel.floatingOf(context.colorScheme),
      child: _PopupScope(
        platter: _platter,
        press: _press,
        surface: _surface,
        runPicked: _runPicked,
        child: builder(context),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (elevated) {
      return ElevatedSurfaceTheme(
        child: Builder(
          builder: (context) => _buildPopup(context, animation, child),
        ),
      );
    }
    return _buildPopup(context, animation, child);
  }

  Widget _buildPopup(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    final colorScheme = context.colorScheme;
    final glass = LiquidGlassScope.of(context);
    return Stack(
      children: [
        Positioned.fill(child: _buildDismissLayer()),
        _PopupAnchorTracker(
          anchorOf: anchorOf,
          builder: (anchor, safeInsets, child) => CustomSingleChildLayout(
            delegate: _PopupLayoutDelegate(
              anchor: anchor,
              safeInsets: safeInsets,
              placement: placement,
              avoid: avoid,
              pin: _pin,
            ),
            child: _PopupMorph(
              anchor: anchor,
              animation: animation,
              platter: _platter,
              surface: _surface,
              sourceColor: sourceColor,
              sourceImage: sourceImage,
              surfaceColor: SurfaceLevel.floatingOf(colorScheme)
                  .colorOf(colorScheme),
              shadows: glass
                  ? glassMenuShadows(colorScheme)
                  : _cardShadows(colorScheme),
              glass: glass
                  ? (
                      from: LiquidGlassStyle.regular(colorScheme),
                      to: LiquidGlassStyle.menu(colorScheme),
                      rim: LiquidGlassRim.menu(colorScheme),
                      coarse:
                          LiquidGlassScope.qualityOf(context) ==
                          LiquidGlassQuality.standard,
                    )
                  : null,
              child: child,
            ),
          ),
          child: NotificationListener<_PopupUnfoldNotification>(
            onNotification: (_) {
              _unfolded.value = true;
              return true;
            },
            child: child,
          ),
        ),
      ],
    );
  }
}
