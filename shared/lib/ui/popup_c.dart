// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'popup.dart';

class _PopupAnchorTracker extends StatefulWidget {
  const _PopupAnchorTracker({
    required this.anchorOf,
    required this.builder,
    required this.child,
  });

  final PopupAnchorResolver anchorOf;
  final Widget Function(Rect anchor, EdgeInsets safeInsets, Widget child)
  builder;
  final Widget child;

  @override
  State<_PopupAnchorTracker> createState() => _PopupAnchorTrackerState();
}

class _PopupAnchorTrackerState extends State<_PopupAnchorTracker> {
  Rect? _anchor;
  bool _syncScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) {
        return;
      }
      final anchor = widget.anchorOf();
      if (anchor == null || anchor == _anchor) {
        return;
      }
      setState(() {
        _anchor = anchor;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final anchor = _anchor ??= widget.anchorOf() ?? Rect.zero;
    // padding already gives up the keyboard's part of the bottom inset.
    return widget.builder(
      anchor,
      mediaQuery.padding + mediaQuery.viewInsets,
      widget.child,
    );
  }
}

class _PopupLayoutDelegate extends SingleChildLayoutDelegate {
  const _PopupLayoutDelegate({
    required this.anchor,
    required this.safeInsets,
    required this.placement,
    required this.pin,
    this.avoid,
  });

  final Rect anchor;
  final EdgeInsets safeInsets;
  final PopupPlacement placement;
  final Rect? avoid;
  final _PopupPin pin;

  EdgeInsets get _insets => safeInsets + const EdgeInsets.all(_screenMargin);

  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final insets = _insets;
    return BoxConstraints.loose(
      Size(
        math.max(0.0, constraints.maxWidth - insets.horizontal),
        math.max(0.0, constraints.maxHeight - insets.vertical),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final insets = _insets;
    final maxX = size.width - insets.right - childSize.width;
    final maxY = size.height - insets.bottom - childSize.height;
    final pinned = pin.topRightFor(this, size);
    final (x, y) = pinned != null
        ? (pinned.dx - childSize.width, pinned.dy)
        : switch (placement) {
            PopupPlacement.overAnchorEnd => (
              anchor.right - childSize.width,
              anchor.top - _anchorOverlap,
            ),
            PopupPlacement.overAnchorStart => (
              anchor.left,
              anchor.top - _anchorOverlap,
            ),
            PopupPlacement.belowPoint => (
              anchor.left,
              _yBelowPoint(childSize.height, insets.top, maxY),
            ),
          };
    final minY = placement == PopupPlacement.belowPoint
        ? insets.top
        : math.max(safeInsets.top, math.min(insets.top, y));
    final position = Offset(
      x.clamp(insets.left, math.max(insets.left, maxX)),
      y.clamp(minY, math.max(minY, maxY)),
    );
    if (pinned == null) {
      pin.hold(this, size, position.translate(childSize.width, 0));
    }
    return position;
  }

  double _yBelowPoint(double height, double minY, double maxY) {
    final avoid = this.avoid;
    if (avoid != null) {
      final above = avoid.top - _avoidGap - height;
      if (above >= minY) {
        return above;
      }
      final below = avoid.bottom + _avoidGap;
      if (below <= maxY) {
        return below;
      }
    }
    if (anchor.bottom > maxY && anchor.top - height >= minY) {
      return anchor.top - height;
    }
    return anchor.bottom;
  }

  bool _placesLike(_PopupLayoutDelegate other) {
    return other.anchor == anchor &&
        other.safeInsets == safeInsets &&
        other.placement == placement &&
        other.avoid == avoid;
  }

  @override
  bool shouldRelayout(_PopupLayoutDelegate oldDelegate) {
    return !_placesLike(oldDelegate) || oldDelegate.pin != pin;
  }
}

/// Keeps the top right corner the menu levels stack from while a sub menu unfolds.
class _PopupPin {
  _PopupLayoutDelegate? _placement;
  Size _size = Size.zero;
  Offset _topRight = Offset.zero;

  Offset? topRightFor(_PopupLayoutDelegate placement, Size size) {
    final held = _placement;
    if (held == null || size != _size || !held._placesLike(placement)) {
      return null;
    }
    return _topRight;
  }

  void hold(_PopupLayoutDelegate placement, Size size, Offset topRight) {
    _placement = placement;
    _size = size;
    _topRight = topRight;
  }
}
