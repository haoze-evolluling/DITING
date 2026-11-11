/// App-wide scroll activity gate.
///
/// Periodic dashboard data (speed curve, memory, log/traffic aggregates) writes new state on a
/// timer, and each write repaints a card and may run synchronous FFI/SQLite work on the UI
/// isolate. When that lands in the middle of a fling it blocks the frame, the ballistic
/// simulation catches up in one step and the list appears to stop dead instead of coasting.
/// Pollers consult [ScrollActivityGate.isScrolling] and defer their work until the list is still.
library;

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Tracks whether any top-level scrollable is dragging or coasting.
class ScrollActivityGate {
  ScrollActivityGate._();

  static int _active = 0;
  static final List<VoidCallback> _idle = <VoidCallback>[];

  /// True while a top-level list is being dragged or is still coasting from a fling.
  static bool get isScrolling => _active > 0;

  /// Runs [callback] now, or once scrolling stops when a list is in motion.
  static void whenIdle(VoidCallback callback) {
    if (_active == 0) {
      callback();
      return;
    }
    _idle.add(callback);
  }

  static void _begin() => _active++;

  static void _end() {
    if (_active == 0) return;
    _active--;
    // A drag hands off to the fling as an end followed by a start in the same gesture turn;
    // deferring one microtask lets that handoff be counted before deciding the list is still.
    if (_active == 0) scheduleMicrotask(_flushIfIdle);
  }

  /// The notification stream is the authority; this clears a counter left high when a scrollable
  /// is torn down mid-drag without emitting an end notification.
  static void _reset() {
    if (_active == 0) return;
    _active = 0;
    _flush();
  }

  static void _flushIfIdle() {
    if (_active != 0) return;
    _flush();
  }

  static void _flush() {
    if (_idle.isEmpty) return;
    final pending = List<VoidCallback>.of(_idle);
    _idle.clear();
    for (final callback in pending) {
      callback();
    }
  }

  /// Drops all state; [ScrollActivityScope] calls it when torn down so a scroll still in flight
  /// during teardown cannot leave the process-wide gate stuck on for the next app/test.
  static void reset() {
    _active = 0;
    _idle.clear();
  }

  /// Feeds a [NotificationListener] the raw scroll stream. Only top-level scrollables count, so a
  /// nested horizontal strip cannot leave the gate stuck.
  static bool handle(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _begin();
    } else if (notification is ScrollEndNotification) {
      _end();
    } else if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _reset();
    }
    return false;
  }
}

/// Installs [ScrollActivityGate] above the app's scrollables.
class ScrollActivityScope extends StatefulWidget {
  const ScrollActivityScope({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollActivityScope> createState() => _ScrollActivityScopeState();
}

class _ScrollActivityScopeState extends State<ScrollActivityScope> {
  @override
  void dispose() {
    ScrollActivityGate.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: ScrollActivityGate.handle,
      child: widget.child,
    );
  }
}
