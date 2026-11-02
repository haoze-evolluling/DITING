// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'snap_sheet.dart';

class _SnapSheet extends StatefulWidget {
  const _SnapSheet({required this.route});

  final SnapSheetRoute<dynamic> route;

  @override
  State<_SnapSheet> createState() => _SnapSheetState();
}

class _SnapSheetState extends State<_SnapSheet>
    with SingleTickerProviderStateMixin {
  late final _model = _SheetModel(route: widget.route, vsync: this);
  late final _scrollController = _SheetScrollController(
    model: _model,
    initialScrollOffset: widget.route.initialScrollOffset,
  );

  Duration? _lastWheel;

  @override
  void initState() {
    super.initState();
    widget.route.animation!.addStatusListener(_handleRouteStatus);
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _model.stop();
    }
  }

  @override
  void dispose() {
    widget.route.animation!.removeStatusListener(_handleRouteStatus);
    _scrollController.dispose();
    _model.dispose();
    super.dispose();
  }

  ScrollController _createScrollController({double initialScrollOffset = 0}) {
    return _SheetScrollController(
      model: _model,
      initialScrollOffset: initialScrollOffset,
    );
  }

  /// Sees the content's scrolls too, so a turn the content started never moves the sheet.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) {
      return;
    }
    final last = _lastWheel;
    _lastWheel = event.timeStamp;
    if (last != null && event.timeStamp - last < _wheelTurnGap) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _model.settleTowards(event.scrollDelta.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final sheetColor = SurfaceLevel.page.colorOf(context.colorScheme);
    final theme = Theme.of(context);
    Widget content = route.builder(context, _scrollController);
    if (route.fitsContent) {
      content = PrimaryScrollController(
        controller: _scrollController,
        automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
        child: content,
      );
    }
    final sheet = Listener(
      onPointerSignal: _handlePointerSignal,
      child: GestureDetector(
        onVerticalDragUpdate: (details) =>
            _model.dragBy(-details.primaryDelta!, stretches: true),
        onVerticalDragEnd: (details) =>
            _model.dragEnd(-(details.primaryVelocity ?? 0)),
        onVerticalDragCancel: () => _model.dragEnd(0),
        child: ClipRSuperellipse(
          borderRadius: AppRadius.top(AppCorner.xxl),
          child: Theme(
            data: theme.copyWith(scaffoldBackgroundColor: sheetColor),
            child: Material(
              color: sheetColor,
              child: _SheetContent(
                model: _model,
                child: _WithoutKeyboard(
                  child: SheetProvider(
                    type: SheetType.bottomSheet,
                    child: SheetOverhangScope(
                      overhang: _model.lift,
                      fitsContent: route.fitsContent,
                      child: SheetDismissScope(
                        handler: route._dismissHandler,
                        child: SheetScrollScope(
                          createController: _createScrollController,
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return SafeArea(
      bottom: false,
      child: _KeyboardViewport(
        model: _model,
        child: RepaintBoundary(child: sheet),
      ),
    );
  }
}

/// The sheet makes room for the keyboard itself, so nothing inside it does.
class _WithoutKeyboard extends StatelessWidget {
  const _WithoutKeyboard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).removeViewInsets(removeBottom: true),
      child: child,
    );
  }
}

class _KeyboardViewport extends StatelessWidget {
  const _KeyboardViewport({required this.model, required this.child});

  final _SheetModel model;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = model.route;
    return _SheetViewport(
      model: model,
      keyboard: MediaQuery.viewInsetsOf(context).bottom,
      presentation: route.animation!,
      cover: route.secondaryAnimation!,
      covering: route._coveringSheet,
      child: child,
    );
  }
}

/// Keyboard, presentation and stacked sheets move the sheet as painted; only height lays it out.
class _SheetViewport extends SingleChildRenderObjectWidget {
  const _SheetViewport({
    required this.model,
    required this.keyboard,
    required this.presentation,
    required this.cover,
    required this.covering,
    required super.child,
  });

  final _SheetModel model;
  final double keyboard;
  final Animation<double> presentation;
  final Animation<double> cover;
  final ValueListenable<SnapSheetRoute<dynamic>?> covering;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSheetViewport(
      model: model,
      keyboard: keyboard,
      presentation: presentation,
      cover: cover,
      covering: covering,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSheetViewport renderObject,
  ) {
    renderObject
      ..model = model
      ..keyboard = keyboard
      ..presentation = presentation
      ..cover = cover
      ..covering = covering;
  }
}

class _RenderSheetViewport extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderSheetViewport({
    required _SheetModel model,
    required double keyboard,
    required Animation<double> presentation,
    required Animation<double> cover,
    required ValueListenable<SnapSheetRoute<dynamic>?> covering,
  }) : _model = model,
       _keyboard = keyboard,
       _presentation = presentation,
       _cover = cover,
       _covering = covering;

  _SheetModel _model;
  double _keyboard;
  Animation<double> _presentation;
  Animation<double> _cover;
  ValueListenable<SnapSheetRoute<dynamic>?> _covering;

  final _layer = LayerHandle<TransformLayer>();
  double _shown = 0;

  set model(_SheetModel value) {
    if (identical(value, _model)) {
      return;
    }
    if (attached) {
      _model.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _model = value;
    markNeedsLayout();
  }

  set keyboard(double value) {
    if (value == _keyboard) {
      return;
    }
    _keyboard = value;
    markNeedsLayout();
  }

  set presentation(Animation<double> value) {
    if (identical(value, _presentation)) {
      return;
    }
    if (attached) {
      _presentation.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _presentation = value;
    markNeedsPaint();
  }

  set cover(Animation<double> value) {
    if (identical(value, _cover)) {
      return;
    }
    if (attached) {
      _cover.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _cover = value;
    markNeedsPaint();
  }

  set covering(ValueListenable<SnapSheetRoute<dynamic>?> value) {
    if (identical(value, _covering)) {
      return;
    }
    if (attached) {
      _covering.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _covering = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _model.addListener(markNeedsLayout);
    _presentation.addListener(markNeedsPaint);
    _cover.addListener(markNeedsPaint);
    _covering.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _model.removeListener(markNeedsLayout);
    _presentation.removeListener(markNeedsPaint);
    _cover.removeListener(markNeedsPaint);
    _covering.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    var limit = _model.beginLayout(size.height, _keyboard);
    final content = _model._content;
    // The limit reaches the content outside its constraints, which may not have changed.
    if (content != null &&
        (content._limit != limit || _model._measureRoom != null)) {
      invokeLayoutCallback<BoxConstraints>((_) => content.markNeedsLayout());
    }
    var height = _model.height;
    _layoutSheet(height);
    if (content != null && _model.releaseLimit()) {
      limit = _model._contentLimit;
      invokeLayoutCallback<BoxConstraints>((_) => content.markNeedsLayout());
      _layoutSheet(height);
    }
    // Within the limit only the sheet around the content needs a new layout.
    if (_model.fitsContent) {
      _model.fitContent();
      final fitted = _model.height;
      if (fitted != height && fitted <= limit) {
        height = fitted;
        _layoutSheet(height);
      }
    }
    _model.endLayout();
  }

  /// Never tight, so a change in the content's height reaches this layout.
  void _layoutSheet(double height) {
    _shown = height;
    child?.layout(
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
      parentUsesSize: true,
    );
  }

  Matrix4 get _transform {
    final sheet = math.max(_shown, _model.minHeight) + _keyboard;
    final cover = _covering.value == null ? 0.0 : _cover.value;
    final scale = 1 - (1 - stackedSheetScale) * cover;
    final below = math.max(_model.minHeight - _shown, 0.0);
    final top =
        size.height -
        sheet +
        below +
        (1 - _presentation.value) * sheet -
        stackedSheetPeek * cover;
    return Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(size.width / 2 * (1 - scale), top, 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      _layer.layer = null;
      return;
    }
    _layer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: _layer.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    // A mouse may hit test between frames, before the sheet is laid out.
    if (child == null || !child.hasSize) {
      return false;
    }
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}

/// The surface fills what the content leaves, the keyboard's part included.
class _SheetContent extends SingleChildRenderObjectWidget {
  const _SheetContent({required this.model, required super.child});

  final _SheetModel model;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSheetContent(model);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSheetContent renderObject,
  ) {
    renderObject.model = model;
  }
}

class _RenderSheetContent extends RenderProxyBox {
  _RenderSheetContent(this._model);

  _SheetModel _model;
  double? _limit;

  _SheetModel get model => _model;

  set model(_SheetModel value) {
    if (identical(value, _model)) {
      return;
    }
    if (attached) {
      _release();
      value._content = this;
    }
    _model = value;
    markNeedsLayout();
  }

  void _release() {
    if (identical(_model._content, this)) {
      _model._content = null;
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _model._content = this;
  }

  @override
  void detach() {
    _release();
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final limit = _limit = model._contentLimit;
    final child = this.child;
    if (child != null) {
      final room = model._measureRoom;
      if (room != null) {
        model._measureRoom = null;
        child.layout(
          BoxConstraints(minWidth: width, maxWidth: width, maxHeight: room),
          parentUsesSize: true,
        );
        model._measured(child.size.height, room);
      }
      child.layout(
        model.fitsContent
            ? BoxConstraints(minWidth: width, maxWidth: width, maxHeight: limit)
            : BoxConstraints(
                maxWidth: width,
                minHeight: limit,
                maxHeight: limit,
              ),
        parentUsesSize: true,
      );
      model.contentHeight = child.size.height;
    }
    size = constraints.biggest;
  }
}
