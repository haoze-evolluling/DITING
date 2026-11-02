// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'popup.dart';

class _CommonPopupMenuState extends State<CommonPopupMenu>
    with SingleTickerProviderStateMixin {
  /// 0 at the item to 1 at its card, on one spring, so a fold mid-unfold turns around.
  late final _unfold = AnimationController.unbounded(vsync: this, value: 1);
  late final Animation<double> _items = _unfold.drive(const _Span(0.05, 0.4));
  late final Animation<double> _arrow = _unfold.drive(_arrowTurns);

  ValueListenable<bool>? _platter;
  late Listenable _motion = _unfold;
  _CarriedPress? _carried;
  _PopupSurface? _surface;
  ValueSetter<VoidCallback>? _runPicked;

  final List<_MenuStep> _path = [];
  bool _folding = false;
  final _menuKey = GlobalKey();
  final _cardKeys = <GlobalKey>[];
  final _checkedKey = GlobalKey();
  ScrollController? _lazyController;

  int? _pressed;
  Timer? _dwell;

  bool _landed = false;
  bool _carrying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealChecked());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _PopupScope.maybeOf(context);
    final platter = scope?.platter;
    if (platter != _platter) {
      _platter = platter;
      _motion = Listenable.merge([_unfold, ?platter]);
    }
    _runPicked = scope?.runPicked;
    _carried = scope?.press
      ?..onMove = _slideCarried
      ..onRelease = _releaseCarried
      ..onCancel = _cancelCarried;
    _surface = scope?.surface?..rectIn = _topCardIn;
  }

  @override
  void dispose() {
    _carried
      ?..onMove = null
      ..onRelease = null
      ..onCancel = null;
    _surface?.rectIn = null;
    _dwell?.cancel();
    _unfold.dispose();
    _lazyController?.dispose();
    super.dispose();
  }

  /// A capped menu builds only the rows in view, so its rows must share one height.
  bool _buildsLazily(_MenuLevel level) =>
      widget.maxVisibleItems != null &&
      level.owner == null &&
      level.items.every(
        (item) =>
            item.subItems.isEmpty &&
            item.subtitle == null &&
            item.section == null,
      );

  void _revealChecked() {
    final row = _checkedKey.currentContext;
    if (!mounted || row == null) {
      return;
    }
    // Whole rows above, not centring, keep the half row a label cut at the foot.
    final visible = _maxVisibleItems;
    final alignment = (visible ~/ 2) / (visible - 0.5);
    Scrollable.maybeOf(row)?.position
        .ensureVisible(row.findRenderObject()!, alignment: alignment);
  }

  double _rowExtentOf(BuildContext context) =>
      _rowPadding(arrow: false).vertical +
      MediaQuery.textScalerOf(context).scale(_labelStyle.leading);

  int get _maxVisibleItems => widget.maxVisibleItems ?? _defaultMaxVisibleItems;

  double _maxHeightOf(BuildContext context, _MenuLevel level) {
    if (level.owner != null) {
      return double.infinity;
    }
    return 2 * _cardInset + (_maxVisibleItems + 0.5) * _rowExtentOf(context);
  }

  double _lazyWidthOf(BuildContext context, List<CommonPopupMenuItem> items) {
    final style = _labelStyle.of(context);
    final root = DefaultTextStyle.of(context).style.merge(style);
    final textScaler = MediaQuery.textScalerOf(context);
    final boldText = MediaQuery.boldTextOf(context);
    final limit = _maxWidth - 2 * _cardInset;
    var width = 0.0;
    for (final item in items) {
      if (_labelWidths.length >= 1024) {
        _labelWidths.clear();
      }
      final label = _labelWidths[(item.label, root, textScaler, boldText)] ??=
          EmojiText.widthOf(context, item.label, root);
      final checked = item.checked == true;
      final row =
          _rowPadding(arrow: checked).horizontal +
          (item.glyph != null ? _iconSize + (widget.dense ? 10 : 12) : 0) +
          label +
          (checked ? 8 + _submenuArrowSize : 0);
      width = math.max(width, row);
      if (width >= limit) {
        break;
      }
    }
    return width;
  }

  Widget _buildLazyContent(BuildContext context, _MenuLevel level) {
    final items = level.items;
    final extent = _rowExtentOf(context);
    final visible = _maxVisibleItems;
    final height = math.min(items.length, visible + 0.5) * extent;
    final controller = _lazyController ??= () {
      final checked = items.indexWhere((item) => item.checked == true);
      return ScrollController(
        initialScrollOffset: ((checked - visible ~/ 2) * extent).clamp(
          0.0,
          math.max(0.0, items.length * extent - height),
        ),
      );
    }();
    return SizedBox(
      width: _lazyWidthOf(context, items),
      height: height,
      child: ListView.builder(
        controller: controller,
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        itemExtent: extent,
        itemCount: items.length,
        itemBuilder: (context, index) =>
            _buildItem(context, items[index], index, active: true),
      ),
    );
  }

  List<_MenuLevel> _resolveLevels() {
    final levels = [
      _MenuLevel(
        items: widget.items,
        top: 0,
        fromWidth: _minWidth,
        minWidth: _minWidth,
        maxWidth: _maxWidth,
      ),
    ];
    for (final step in _path) {
      final parent = levels.last;
      if (step.index >= parent.items.length) {
        break;
      }
      final item = parent.items[step.index];
      if (item.subItems.isEmpty) {
        break;
      }
      final fromWidth = math.max(step.cardWidth, parent.minWidth);
      final minWidth = fromWidth * _levelWidthScale;
      levels.add(
        _MenuLevel(
          items: item.subItems,
          owner: item,
          step: step,
          top: math.max(0, step.itemTop - _cardInset),
          fromWidth: fromWidth,
          minWidth: minWidth,
          maxWidth: math.max(minWidth, _maxWidth),
        ),
      );
    }
    return levels;
  }

  GlobalKey _cardKeyAt(int index) {
    while (_cardKeys.length <= index) {
      _cardKeys.add(GlobalKey());
    }
    return _cardKeys[index];
  }

  /// Where the top sub menu's card stands in the popup, for it to return from.
  Rect? _topCardIn(RenderBox popup) {
    final top = _resolveLevels().length - 1;
    if (top == 0 || top >= _cardKeys.length) {
      return null;
    }
    final card = _cardKeys[top].currentContext?.findRenderObject();
    if (card is! _RenderPopupMenuCard || !card.hasSize || !card.attached) {
      return null;
    }
    return MatrixUtils.transformRect(card.getTransformTo(popup), card._rect);
  }

  void _push(BuildContext itemContext, int index) {
    final itemBox = itemContext.findRenderObject() as RenderBox?;
    final stackBox = context.findRenderObject() as RenderBox?;
    final placed =
        itemBox != null &&
        stackBox != null &&
        itemBox.hasSize &&
        stackBox.hasSize;
    const _PopupUnfoldNotification().dispatch(context);
    setState(() {
      _folding = false;
      _path.add(
        _MenuStep(
          index: index,
          itemTop: placed
              ? itemBox.localToGlobal(Offset.zero, ancestor: stackBox).dy
              : 0,
          itemHeight: placed ? itemBox.size.height : 0,
          cardWidth: placed ? itemBox.size.width + 2 * _cardInset : _minWidth,
        ),
      );
    });
    _unfold.value = 0;
    _unfoldTop();
  }

  TickerFuture _springTo(double target, SpringDescription spring) {
    return _unfold.animateWith(
      SpringSimulation(spring, _unfold.value, target, _unfold.velocity),
    );
  }

  void _unfoldTop() {
    // A spring stops within its tolerance; the card lands on its bounds.
    _springTo(1, _unfoldSpring).then((_) {
      if (mounted && !_folding) {
        _unfold.value = 1;
      }
    });
  }

  void _pop() {
    if (_path.isEmpty || _folding) {
      return;
    }
    setState(() => _folding = true);
    _springTo(0, _foldSpring).then((_) {
      if (!mounted || !_folding) {
        return;
      }
      setState(() {
        _folding = false;
        final step = _path.removeLast();
        if (_pressed == _headerIndex) {
          _pressed = step.index;
        }
        _unfold.value = 1;
      });
    });
  }

  void _toggleTop() {
    if (!_folding) {
      _pop();
      return;
    }
    setState(() => _folding = false);
    _unfoldTop();
  }

  void _select(VoidCallback onPressed) {
    Navigator.of(context).pop();
    final runPicked = _runPicked;
    if (runPicked == null) {
      onPressed();
    } else {
      runPicked(onPressed);
    }
  }

  /// Hit tests where the menu paints, which a press swells or stretches.
  _MenuRow? _rowAt(Offset position) {
    final box = _menuKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    final painted = ElasticPress.paintBoundsOf(box);
    final local = box.globalToLocal(position);
    final result = BoxHitTestResult();
    box.hitTest(
      result,
      position: Offset(
        (local.dx - painted.left) * box.size.width / painted.width,
        (local.dy - painted.top) * box.size.height / painted.height,
      ),
    );
    for (final entry in result.path) {
      if (entry.target case RenderMetaData(metaData: final _MenuRow row)) {
        return row;
      }
    }
    return null;
  }

  bool _startPress(Offset position) {
    final row = _rowAt(position);
    if (row == null) {
      return false;
    }
    _hold(row);
    return true;
  }

  void _slidePress(Offset position) {
    final row = _rowAt(position);
    final index = row?.onTap == null ? null : row!.index;
    if (index == _pressed) {
      return;
    }
    if (index != null) {
      HapticFeedback.selectionClick();
    }
    _hold(row);
  }

  void _hold(_MenuRow? row) {
    _dwell?.cancel();
    _landed = false;
    final onTap = row?.onTap;
    final index = onTap == null ? null : row!.index;
    setState(() => _pressed = index);
    if (onTap == null || !row!.togglesSubMenu) {
      return;
    }
    _dwell = Timer(_dwellDuration, () {
      if (!mounted || _pressed != index) {
        return;
      }
      onTap();
      HapticFeedback.selectionClick();
      setState(() {
        _pressed = _headerIndex;
        _landed = true;
      });
    });
  }

  void _endPress(Offset position) {
    final onTap = _landed ? null : _rowAt(position)?.onTap;
    _cancelPress();
    onTap?.call();
  }

  void _cancelPress() {
    _dwell?.cancel();
    _landed = false;
    if (mounted && _pressed != null) {
      setState(() => _pressed = null);
    }
  }

  ElasticPressHandle? get _elastic {
    final menu = _menuKey.currentContext;
    return menu == null ? null : ElasticPress.maybeOf(menu);
  }

  bool get _platterShows => _platter?.value ?? false;

  void _slideCarried(Offset position) {
    if (!_carrying && !_platterShows) {
      _carrying = true;
      _elastic?.press(position);
    }
    if (_carrying) {
      _elastic?.drag(position);
    }
    _slidePress(position);
  }

  void _releaseCarried(Offset position) {
    _carrying = false;
    _elastic?.release();
    _endPress(position);
  }

  void _cancelCarried() {
    _carrying = false;
    _elastic?.release();
    _cancelPress();
  }

  @override
  Widget build(BuildContext context) {
    final levels = _resolveLevels();
    final topIndex = levels.length - 1;
    return PopScope(
      canPop: topIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _pop();
        }
      },
      // The platter clips the menu as it opens and does not swell, so a swell would cut its edges.
      child: ValueListenableBuilder<bool>(
        valueListenable: _platter ?? const AlwaysStoppedAnimation(false),
        builder: (_, platter, child) =>
            ElasticPress(enabled: !platter, pullPastEdges: true, child: child!),
        child: RawGestureDetector(
          key: _menuKey,
          gestures: {
            _RowPressRecognizer:
                GestureRecognizerFactoryWithHandlers<_RowPressRecognizer>(
                  () => _RowPressRecognizer(debugOwner: this),
                  (recognizer) => recognizer
                    ..onStart = _startPress
                    ..onUpdate = _slidePress
                    ..onEnd = _endPress
                    ..onCancel = _cancelPress,
                ),
          },
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              for (var index = 0; index <= topIndex; index++)
                Padding(
                  key: ValueKey(index),
                  padding: EdgeInsets.only(top: levels[index].top),
                  child: _buildLevel(
                    context,
                    levels[index],
                    cardKey: _cardKeyAt(index),
                    depth: topIndex - index,
                    pivot: index < topIndex
                        ? _path[index].itemTop - levels[index].top
                        : 0,
                    covered: index < topIndex ? _path[index].index : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
