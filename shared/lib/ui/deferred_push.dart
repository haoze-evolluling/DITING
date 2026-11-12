// Portions derived from FlClash (https://github.com/chen08209/FlClash), Copyright (c) the FlClash authors, GPL-3.0-or-later.
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:diting_shared/ui/motion.dart';
import 'package:diting_shared/ui/navigator.dart';

const arrivalHoldLimit = Duration(milliseconds: 200);

/// Starts a push transition one frame after the page is first built, so a long
/// first build does not swallow the start of the transition.
mixin DeferredPushRouteMixin<T> on TransitionRoute<T> {
  _TickerCapture? _vsync;
  var _takesHolds = false;
  List<Completer<void>>? _arrivalHolds;

  @override
  AnimationController createAnimationController() {
    final vsync = _vsync = _TickerCapture(navigator!);
    return AnimationController(
      duration: transitionDuration,
      reverseDuration: reverseTransitionDuration,
      debugLabel: debugLabel,
      vsync: vsync,
    );
  }

  @override
  TickerFuture didPush() {
    final ticker = _vsync?.ticker;
    if (ticker == null || ticker.muted) {
      return super.didPush();
    }
    ticker.muted = true;
    _takesHolds = true;
    final holds = _arrivalHolds = [];
    final pushed = super.didPush();
    final context = navigator!.context;
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      _takesHolds = false;
      if (holds.isNotEmpty) {
        await Future.wait([for (final hold in holds) hold.future])
            .timeout(arrivalHoldLimit, onTimeout: () => const []);
        if (!context.mounted) {
          return;
        }
      }
      _arrivalHolds = null;
      ticker.muted = !TickerMode.getValuesNotifier(context).value.enabled;
    });
    return pushed;
  }
}

/// Holds the transition of its page's route, and of the sheets carrying it,
/// until [ready], for at most [arrivalHoldLimit].
/// Counts only in the first frame of a page its route pushed.
class ArrivalHold extends StatefulWidget {
  const ArrivalHold({super.key, required this.ready, required this.child});

  final bool ready;
  final Widget child;

  @override
  State<ArrivalHold> createState() => _ArrivalHoldState();
}

class _ArrivalHoldState extends State<ArrivalHold> {
  var _checked = false;
  Completer<void>? _hold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) {
      return;
    }
    _checked = true;
    if (widget.ready) {
      return;
    }
    final heldRoutes = [
      for (final route in routesCarrying(context))
        if (route case final DeferredPushRouteMixin<Object?> held
            when held._takesHolds)
          held,
    ];
    if (heldRoutes.isNotEmpty) {
      final hold = _hold = Completer();
      for (final route in heldRoutes) {
        route._arrivalHolds!.add(hold);
      }
    }
  }

  @override
  void didUpdateWidget(ArrivalHold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready) {
      _release();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    final hold = _hold;
    _hold = null;
    if (hold != null && !hold.isCompleted) {
      hold.complete();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TickerCapture implements TickerProvider {
  _TickerCapture(this._parent);

  final NavigatorState _parent;
  Ticker? ticker;
  Duration _lead = Duration.zero;
  Duration? _last;

  // A run started between frames first ticks at zero, showing the frame on
  // screen again; its start value stays, as the route below links to it.
  @override
  Ticker createTicker(TickerCallback onTick) {
    return ticker = _parent.createTicker((elapsed) {
      final last = _last;
      if (elapsed == Duration.zero) {
        _lead = frameIntervalOf(_parent.context);
      } else if (last != null && elapsed <= last) {
        _lead = Duration.zero;
      }
      _last = elapsed;
      onTick(elapsed + _lead);
    });
  }
}
