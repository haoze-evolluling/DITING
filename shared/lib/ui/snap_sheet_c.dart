// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'snap_sheet.dart';

class _SheetScrollController extends ScrollController
    with SheetScrollController {
  _SheetScrollController({required this.model, super.initialScrollOffset});

  final _SheetModel model;

  @override
  ValueListenable<bool> get sheetOpen => model.open;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SheetScrollPosition(
      physics: _SheetContentPhysics(parent: physics),
      context: context,
      oldPosition: oldPosition,
      initialPixels: initialScrollOffset,
      model: model,
    );
  }
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext
    with ScrubbableScrollPosition {
  _SheetScrollPosition({
    required this.model,
    required super.physics,
    required super.context,
    super.initialPixels,
    super.oldPosition,
  }) {
    model.settling.addListener(_followSettling);
  }

  final _SheetModel model;

  bool get _isDragged => activity is DragScrollActivity;

  bool get _isReversed => axisDirectionIsReversed(axisDirection);

  /// A reverse list reaches the top edge at its maximum offset, not its minimum.
  bool get _contentScrolled {
    if (!hasContentDimensions) {
      return false;
    }
    return _isReversed
        ? pixels < maxScrollExtent - precisionErrorTolerance
        : pixels > minScrollExtent + precisionErrorTolerance;
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    final atEdge = !_contentScrolled;
    return _SheetContentDrag(
      this,
      super.drag(details, dragCancelCallback),
      startedAtEdge: atEdge,
    );
  }

  @override
  void pointerScroll(double delta) {
    if (model.isSettling && !model.isOpen) {
      return;
    }
    final grow = _isReversed ? -delta : delta;
    if (!isScrubbing && !_contentScrolled && (grow < 0 || !model.isOpen)) {
      model.settleTowards(grow);
      return;
    }
    super.pointerScroll(delta);
  }

  /// Keeps a reverse list, which hangs from its bottom, fixed to the top edge.
  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) {
    final grown = newPosition.viewportDimension - oldPosition.viewportDimension;
    var pixels = newPosition.pixels;
    if (_isReversed && grown != 0) {
      pixels = clampDouble(
        pixels - grown,
        newPosition.minScrollExtent,
        newPosition.maxScrollExtent,
      );
    }
    final corrected = physics.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition.copyWith(pixels: pixels),
      isScrolling: activity!.isScrolling,
      velocity: activity!.velocity,
    );
    if (corrected == newPosition.pixels) {
      return true;
    }
    correctPixels(corrected);
    return false;
  }

  void _followSettling() {
    if (model.settling.value) {
      if (activity.runtimeType == IdleScrollActivity) {
        goIdle();
      }
    } else if (activity is _SettlingScrollActivity) {
      goIdle();
    }
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    if (newActivity.runtimeType == IdleScrollActivity && model.settling.value) {
      newActivity!.dispose();
      super.beginActivity(_SettlingScrollActivity(this));
      return;
    }
    super.beginActivity(newActivity);
  }

  @override
  void dispose() {
    model.settling.removeListener(_followSettling);
    super.dispose();
  }
}

/// As UIKit: a drag up grows the sheet then scrolls; a drag down takes it only from the top.
class _SheetContentDrag implements Drag {
  _SheetContentDrag(
    this._position,
    this._content, {
    required this.startedAtEdge,
  });

  final _SheetScrollPosition _position;
  final Drag _content;
  final bool startedAtEdge;

  bool _sheetHeld = false;

  _SheetModel get _sheet => _position.model;

  @override
  void update(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta == 0 || _position.isScrubbing) {
      _content.update(details);
      return;
    }
    final grow = -delta;
    if (grow > 0) {
      if (!_sheetHeld && (_position._contentScrolled || _sheet.isOpen)) {
        _content.update(details);
        return;
      }
      _sheetHeld = true;
      final rest = grow - _sheet.dragBy(grow);
      if (rest > precisionErrorTolerance) {
        _sheetHeld = false;
        _content.update(
          DragUpdateDetails(
            sourceTimeStamp: details.sourceTimeStamp,
            delta: Offset(0, -rest),
            primaryDelta: -rest,
            globalPosition: details.globalPosition,
            localPosition: details.localPosition,
          ),
        );
      }
      return;
    }
    if (!_sheetHeld && (!startedAtEdge || _position._contentScrolled)) {
      _content.update(details);
      return;
    }
    _sheetHeld = true;
    _sheet.dragBy(grow);
  }

  @override
  void end(DragEndDetails details) {
    if (!_sheetHeld) {
      _content.end(details);
      _sheet.dragEnd(0);
      return;
    }
    _content.end(
      DragEndDetails(
        primaryVelocity: 0,
        globalPosition: details.globalPosition,
      ),
    );
    _sheet.dragEnd(-(details.primaryVelocity ?? 0));
  }

  @override
  void cancel() {
    _content.cancel();
    _sheet.dragEnd(0);
  }
}

/// Keeps a drag that grows the sheet alive once the content fits its viewport.
class _SheetContentPhysics extends ScrollPhysics {
  const _SheetContentPhysics({super.parent});

  @override
  _SheetContentPhysics applyTo(ScrollPhysics? ancestor) {
    return _SheetContentPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    return (position is _SheetScrollPosition && position._isDragged) ||
        super.shouldAcceptUserOffset(position);
  }
}

/// Keeps taps off the rows while the sheet settles, as a fling does.
class _SettlingScrollActivity extends IdleScrollActivity {
  _SettlingScrollActivity(super.delegate);

  @override
  bool get shouldIgnorePointer => true;
}
