// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:math' as math;

import 'package:diting_android/ui/color.dart';
import 'package:diting_android/ui/context.dart';
import 'package:diting_android/ui/input.dart';
import 'package:diting_android/ui/liquid_glass.dart';
import 'package:diting_android/ui/motion.dart';
import 'package:diting_android/ui/navigation_dock.dart';
import 'package:diting_android/ui/sheet_navigator.dart';
import 'package:diting_android/ui/shape.dart';
import 'package:diting_android/ui/surface.dart';
import 'package:diting_android/ui/typography.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
part 'dialog_a.dart';
part 'dialog_b.dart';

const double _actionGap = 8;
const double _actionInset = 16;
const double _actionHeight = 48;
const double _textInset = 30;
const double _alertWidth = 348;
const double _contentMaxWidth = 300;
const double _dialogInset = 40;
const double _fieldInputGap = 4;
const double _pressGrowth = 4;
const double _pressPull = 3;
const double _pressedFillShare = 0.4;
const double _pressedDarkDefaultShare = 0.5;

const _alertDuration = Duration(milliseconds: 404);
const double _alertEntryScale = 1.2;
final _alertSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 275),
  ),
  seconds: _alertDuration.inMicroseconds / Duration.microsecondsPerSecond,
);

Future<T?> showFloatingDialog<T>({
  required BuildContext context,
  required Widget child,
  bool dismissible = true,
}) {
  return sheetNavigatorOf(context).push<T>(
    _AlertRoute<T>(
      barrierColor: context.colorScheme.alertScrim,
      barrierDismissible: dismissible,
      barrierLabel: dismissible
          ? MaterialLocalizations.of(context).modalBarrierDismissLabel
          : null,
      builder: (context) => SurfaceScope(
        level: SurfaceLevel.floatingOf(context.colorScheme),
        child: child,
      ),
    ),
  );
}

void popFloatingDialog<T>(BuildContext context, [T? result]) {
  sheetNavigatorOf(context).pop<T>(result);
}

mixin AlertHostRoute<T> on ModalRoute<T> {}

class _AlertRoute<T> extends PopupRoute<T>
    with AlertMotionRouteMixin<T>, AlertHostRoute<T> {
  _AlertRoute({
    required this.barrierColor,
    required this.barrierDismissible,
    required this.barrierLabel,
    required this.builder,
  });

  @override
  final Color barrierColor;

  @override
  final bool barrierDismissible;

  @override
  final String? barrierLabel;

  final WidgetBuilder builder;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: SafeArea(child: Builder(builder: builder)),
    );
  }
}

mixin AlertMotionRouteMixin<T> on PopupRoute<T> {
  CurvedAnimation? _sprung;

  Animation<double> get _spring => _sprung ??= CurvedAnimation(
    parent: animation!,
    curve: _alertSpring,
    reverseCurve: _alertSpring.flipped,
  );

  VoidCallback? get onBarrierDismiss => null;

  @override
  Duration get transitionDuration => _alertDuration;

  @override
  Widget buildModalBarrier() {
    final barrier = ModalBarrier(
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
      onDismiss: onBarrierDismiss,
    );
    final barrierColor = this.barrierColor;
    if (offstage || barrierColor == null) {
      return barrier;
    }
    return LiquidGlassVeil(
      color: _spring.drive(
        ColorTween(begin: barrierColor.withValues(alpha: 0), end: barrierColor),
      ),
      child: barrier,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _AlertTransition(animation: _spring, child: child);
  }

  @override
  void dispose() {
    _sprung?.dispose();
    super.dispose();
  }
}

class _AlertTransition extends StatefulWidget {
  const _AlertTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_AlertTransition> createState() => _AlertTransitionState();
}

class _AlertTransitionState extends State<_AlertTransition> {
  double? _heldScale;

  double get _scale =>
      _heldScale ??
      _alertEntryScale + (1 - _alertEntryScale) * widget.animation.value;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(_AlertTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      oldWidget.animation.removeStatusListener(_handleStatus);
      widget.animation.addStatusListener(_handleStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    _heldScale = status == AnimationStatus.reverse ? _scale : null;
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassFade(
      opacity: widget.animation,
      child: AnimatedBuilder(
        animation: widget.animation,
        builder: (_, child) => Transform.scale(scale: _scale, child: child),
        child: widget.child,
      ),
    );
  }
}

RenderPhysicalShape? _surfaceIn(RenderObject node) {
  if (node is RenderPhysicalShape) {
    return node;
  }
  RenderPhysicalShape? surface;
  node.visitChildren((child) => surface ??= _surfaceIn(child));
  return surface;
}

Rect _surfaceRectIn(RenderBox box) {
  final surface = _surfaceIn(box);
  if (surface == null) {
    return Offset.zero & box.size;
  }
  return MatrixUtils.transformRect(
    surface.getTransformTo(box),
    Offset.zero & surface.size,
  );
}
