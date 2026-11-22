library;

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ScrollActivityGate {
  ScrollActivityGate._();

  static int _active = 0;
  static final List<VoidCallback> _idle = <VoidCallback>[];

  static bool get isScrolling => _active > 0;

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
    if (_active == 0) scheduleMicrotask(_flushIfIdle);
  }

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

  static void reset() {
    _active = 0;
    _idle.clear();
  }

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
