import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class HapticFeedbackScope extends InheritedWidget {
  const HapticFeedbackScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool isEnabledOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HapticFeedbackScope>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(HapticFeedbackScope oldWidget) =>
      enabled != oldWidget.enabled;
}

abstract final class AppHaptics {
  static final _clock = Stopwatch()..start();
  static int _lastEmissionMs = -1000;

  static const _repeatGuard = Duration(milliseconds: 32);

  static bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  static void tap(BuildContext context) =>
      _emit(context, HapticFeedback.lightImpact);

  static void valueChanged(BuildContext context) =>
      _emit(context, HapticFeedback.lightImpact);

  static void dragStart(BuildContext context) =>
      _emit(context, HapticFeedback.lightImpact);

  static void selection(BuildContext context) =>
      _emit(context, HapticFeedback.selectionClick);

  static void longPress(BuildContext context) =>
      _emit(context, HapticFeedback.mediumImpact);

  static void enabled() {
    if (!_supported) {
      return;
    }
    _lastEmissionMs = _clock.elapsedMilliseconds;
    unawaited(HapticFeedback.lightImpact());
  }

  static void _emit(BuildContext context, Future<void> Function() feedback) {
    if (!_supported || !HapticFeedbackScope.isEnabledOf(context)) {
      return;
    }
    final now = _clock.elapsedMilliseconds;
    if (now - _lastEmissionMs < _repeatGuard.inMilliseconds) {
      return;
    }
    _lastEmissionMs = now;
    unawaited(feedback());
  }
}

class AppHapticTapFeedback extends StatefulWidget {
  const AppHapticTapFeedback({super.key, required this.child});

  final Widget child;

  @override
  State<AppHapticTapFeedback> createState() => _AppHapticTapFeedbackState();
}

class _AppHapticTapFeedbackState extends State<AppHapticTapFeedback> {
  final Map<int, _TapCandidate> _candidates = {};

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: widget.child,
    );
  }

  void _handleDown(PointerDownEvent event) {
    if (!HapticFeedbackScope.isEnabledOf(context) ||
        event.kind != PointerDeviceKind.touch ||
        event.buttons & kPrimaryButton == 0) {
      return;
    }
    final actions = _actionsAt(event);
    if (!actions.tap) {
      return;
    }
    _candidates[event.pointer] = _TapCandidate(
      origin: event.position,
      downAt: event.timeStamp,
      hasLongPress: actions.longPress,
    );
  }

  void _handleMove(PointerMoveEvent event) {
    final candidate = _candidates[event.pointer];
    if (candidate != null &&
        (event.position - candidate.origin).distance > kTouchSlop) {
      candidate.moved = true;
    }
  }

  void _handleUp(PointerUpEvent event) {
    final candidate = _candidates.remove(event.pointer);
    if (candidate == null || candidate.moved) {
      return;
    }
    if (candidate.hasLongPress &&
        event.timeStamp - candidate.downAt > kLongPressTimeout) {
      return;
    }
    AppHaptics.tap(context);
  }

  void _handleCancel(PointerCancelEvent event) {
    _candidates.remove(event.pointer);
  }

  ({bool tap, bool longPress}) _actionsAt(PointerDownEvent event) {
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, event.position, event.viewId);
    var tap = false;
    var longPress = false;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderSemanticsGestureHandler) {
        tap |= target.onTap != null;
        longPress |= target.onLongPress != null;
      } else if (target is RenderSemanticsAnnotations) {
        tap |= target.properties.onTap != null;
        longPress |= target.properties.onLongPress != null;
      }
    }
    return (tap: tap, longPress: longPress);
  }
}

class _TapCandidate {
  _TapCandidate({
    required this.origin,
    required this.downAt,
    required this.hasLongPress,
  });

  final Offset origin;
  final Duration downAt;
  final bool hasLongPress;
  bool moved = false;
}
