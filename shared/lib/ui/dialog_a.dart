// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'dialog.dart';

/// [AlertDialog] takes only a color, so the pane goes where its [Material] lays out its
/// [PhysicalShape].
class _AlertGlass extends SingleChildRenderObjectWidget {
  const _AlertGlass({
    required this.style,
    required this.rim,
    required this.shadows,
    super.child,
  });

  final LiquidGlassStyle style;
  final LiquidGlassRim rim;
  final List<BoxShadow> shadows;

  @override
  _RenderAlertGlass createRenderObject(BuildContext context) {
    return _RenderAlertGlass(style, rim, shadows);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAlertGlass renderObject,
  ) {
    renderObject
      ..style = style
      ..rim = rim
      ..shadows = shadows;
  }
}

class _RenderAlertGlass extends RenderProxyBox {
  _RenderAlertGlass(this._style, this._rim, this._shadows);

  late final _pane = LiquidGlassPane(markNeedsPaint);

  LiquidGlassStyle _style;
  set style(LiquidGlassStyle value) {
    if (value == _style) {
      return;
    }
    _style = value;
    markNeedsPaint();
  }

  LiquidGlassRim _rim;
  set rim(LiquidGlassRim value) {
    if (value == _rim) {
      return;
    }
    _rim = value;
    markNeedsPaint();
  }

  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (listEquals(value, _shadows)) {
      return;
    }
    _shadows = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void dispose() {
    _pane.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_surfaceIn(this) == null) {
      _pane.clear();
    } else {
      final rect = _surfaceRectIn(this).shift(offset);
      // One capture serves the entry's scale and a press.
      _pane.paint(
        context,
        rect,
        shape: LiquidGlassCorners.circular(AppCorner.alert),
        style: _style,
        shadows: _shadows,
        hold: rect.inflate(_pressGrowth + _pressPull),
        steadyFrost: true,
        rim: _rim,
      );
      _rim.paintLine(context.canvas, rect, AppCorner.alert);
    }
    super.paint(context, offset);
  }
}

class CommonDialog extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget? child;

  /// Text buttons laid out as an iOS alert does: last is the filled default, first (cancel) ends a
  /// stack.
  final List<Widget>? actions;
  final EdgeInsets? padding;

  final bool hasFields;

  /// The last action destroys data: red on the plain fill, as in UIKit.
  final bool destructive;

  /// Pane width in dp; `null` keeps the alert's intrinsic sizing. Clamped to what the screen shows.
  final double? width;

  /// Margin between pane and screen edge; `null` keeps [AlertDialog]'s own 40 a side.
  final EdgeInsets? insetPadding;

  const CommonDialog({
    super.key,
    required this.title,
    this.trailing,
    this.actions,
    this.child,
    this.padding,
    this.hasFields = false,
    this.destructive = false,
    this.width,
    this.insetPadding,
  });

  /// [width] clamped to the space the dialog's own inset padding leaves.
  double? _resolvedWidth(BuildContext context) {
    final width = this.width;
    if (width == null) {
      return null;
    }
    final inset = insetPadding?.horizontal ?? _dialogInset * 2;
    return math.min(width, MediaQuery.sizeOf(context).width - inset);
  }

  @override
  Widget build(BuildContext context) {
    final actions = this.actions ?? const <Widget>[];
    final contentInset = hasFields ? _actionInset : _textInset;
    final glass = LiquidGlassScope.of(context);
    final colorScheme = context.colorScheme;
    final fill = glass ? glassFillOf(colorScheme) : null;
    final resolvedWidth = _resolvedWidth(context);
    final dialog = AlertDialog(
      backgroundColor: glass ? Colors.transparent : null,
      insetPadding: insetPadding,
      // A fixed width must go on `AlertDialog.constraints`; a `maxWidth` on `content` is not
      // enough.
      constraints: resolvedWidth == null
          ? null
          : BoxConstraints(minWidth: resolvedWidth, maxWidth: resolvedWidth),
      titleTextStyle: hasFields
          ? AppTextStyle.body.of(context)
          : AppTextStyle.headline.of(context),
      contentTextStyle: AppTextStyle.subheadline
          .of(context)
          .copyWith(
            color: colorScheme.onSurfaceVariant.withValues(
              alpha: colorScheme.brightness == Brightness.dark ? 1 : 0.85,
            ),
          ),
      title: _buildTitle(),
      actions: actions.isEmpty
          ? null
          : [
              AlertActions(
                actions: actions,
                fill: fill,
                destructive: destructive,
              ),
            ],
      actionsPadding: const EdgeInsets.fromLTRB(
        _actionInset,
        0,
        _actionInset,
        _actionInset,
      ),
      titlePadding: const EdgeInsets.fromLTRB(_textInset, 21, _textInset, 0),
      contentPadding:
          padding ??
          EdgeInsets.fromLTRB(
            contentInset,
            hasFields ? 16 : 6,
            contentInset,
            20,
          ),
      content: Container(
        constraints: BoxConstraints(
          maxWidth: resolvedWidth != null
              ? resolvedWidth - contentInset * 2
              : padding == null
              ? _alertWidth - contentInset * 2
              : _contentMaxWidth,
        ),
        width: double.infinity,
        child: SingleChildScrollView(
          child: hasFields
              ? FilledInputTheme(
                  fillColor: fill,
                  borderRadius: AppRadius.all(_actionHeight / 2),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: _textInset - _actionInset - _fieldInputGap,
                    vertical: 12,
                  ),
                  child: child ?? const SizedBox.shrink(),
                )
              : child,
        ),
      ),
    );
    return ElasticPress(
      pullPastEdges: true,
      maxGrowth: _pressGrowth,
      maxPull: _pressPull,
      panelOf: _surfaceRectIn,
      child: glass
          ? _AlertGlass(
              style: LiquidGlassStyle.alert(colorScheme),
              rim: LiquidGlassRim.alert(colorScheme),
              shadows: glassMenuShadows(colorScheme),
              child: dialog,
            )
          : dialog,
    );
  }

  Widget _buildTitle() {
    final trailing = this.trailing;
    if (!hasFields) {
      return trailing == null
          ? Text(title)
          : Row(
              children: [
                Expanded(child: Text(title)),
                trailing,
              ],
            );
    }
    final text = Text(title, textAlign: TextAlign.center);
    if (trailing == null) {
      return SizedBox(width: double.infinity, child: text);
    }
    return _CenteredTitle(title: text, trailing: trailing);
  }
}

/// A title centred on its whole width, beside a control at its end.
class _CenteredTitle extends MultiChildRenderObjectWidget {
  _CenteredTitle({required Widget title, required Widget trailing})
    : super(children: [title, trailing]);

  @override
  _RenderCenteredTitle createRenderObject(BuildContext context) {
    return _RenderCenteredTitle(textDirection: Directionality.of(context));
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCenteredTitle renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _RenderCenteredTitle extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _RenderCenteredTitle({required TextDirection textDirection})
    : _textDirection = textDirection;

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _title => firstChild!;

  RenderBox get _trailing => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _title.getMinIntrinsicWidth(height) +
      _trailing.getMinIntrinsicWidth(height) * 2;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _title.getMaxIntrinsicWidth(height) +
      _trailing.getMaxIntrinsicWidth(height) * 2;

  @override
  double computeMinIntrinsicHeight(double width) => math.max(
    _title.getMinIntrinsicHeight(width),
    _trailing.getMinIntrinsicHeight(width),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(
    _title.getMaxIntrinsicHeight(width),
    _trailing.getMaxIntrinsicHeight(width),
  );

  double _widthOf(BoxConstraints constraints, double side) =>
      constraints.hasBoundedWidth
      ? constraints.maxWidth
      : _title.getMaxIntrinsicWidth(double.infinity) + side * 2;

  BoxConstraints _titleConstraints(double width, double side) =>
      BoxConstraints.tightFor(width: math.max(0.0, width - side * 2));

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final trailing = _trailing.getDryLayout(constraints.loosen());
    final width = _widthOf(constraints, trailing.width);
    final title = _title.getDryLayout(_titleConstraints(width, trailing.width));
    return constraints.constrain(
      Size(width, math.max(title.height, trailing.height)),
    );
  }

  @override
  void performLayout() {
    _trailing.layout(constraints.loosen(), parentUsesSize: true);
    final side = _trailing.size.width;
    final width = _widthOf(constraints, side);
    _title.layout(_titleConstraints(width, side), parentUsesSize: true);
    size = constraints.constrain(
      Size(width, math.max(_title.size.height, _trailing.size.height)),
    );
    final rtl = _textDirection == TextDirection.rtl;
    (_title.parentData! as MultiChildLayoutParentData).offset = Offset(
      side,
      (size.height - _title.size.height) / 2,
    );
    (_trailing.parentData! as MultiChildLayoutParentData).offset = Offset(
      rtl ? 0 : size.width - side,
      (size.height - _trailing.size.height) / 2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

/// Text buttons laid out and filled as [CommonDialog] sets its own.
class AlertActions extends StatelessWidget {
  const AlertActions({
    super.key,
    required this.actions,
    this.fill,
    this.destructive = false,
  });

  final List<Widget> actions;

  final Color? fill;

  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return _AlertActions(
      children: [
        for (final (index, action) in actions.indexed)
          _AlertAction(
            isDefault: !destructive && index == actions.length - 1,
            destructive: destructive && index == actions.length - 1,
            fill: fill,
            child: action,
          ),
      ],
    );
  }
}

class _AlertAction extends StatelessWidget {
  const _AlertAction({
    required this.isDefault,
    required this.destructive,
    required this.fill,
    required this.child,
  });

  final bool isDefault;
  final bool destructive;
  final Color? fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final fill = this.fill ?? context.raisedSurfaceLevel.colorOf(colorScheme);
    final foreground = isDefault
        ? colorScheme.onPrimary
        : destructive
        ? colorScheme.destructive
        : colorScheme.onSurface;
    final background = isDefault ? colorScheme.primary : fill;
    final pressedShare = switch ((isDefault, colorScheme.brightness)) {
      (true, Brightness.dark) => _pressedDarkDefaultShare,
      (false, Brightness.dark) => 1.0,
      _ => _pressedFillShare,
    };
    return TextButtonTheme(
      data: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: foreground,
              disabledForegroundColor: colorScheme.onSurface.withValues(
                alpha: 0.38,
              ),
              textStyle: isDefault
                  ? AppTextStyle.body.of(context, emphasized: true)
                  : AppTextStyle.body
                        .of(context)
                        .copyWith(fontWeight: FontWeight.w500),
              minimumSize: const Size(0, _actionHeight),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: AppShape.full,
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              splashFactory: NoSplash.splashFactory,
            ).copyWith(
              backgroundColor: WidgetStateProperty<Color?>.fromMap({
                WidgetState.disabled: fill,
                WidgetState.pressed: background.withValues(
                  alpha: background.a * pressedShare,
                ),
                WidgetState.any: background,
              }),
              overlayColor: WidgetStateProperty<Color?>.fromMap({
                WidgetState.focused: foreground.withValues(alpha: 0.1),
                WidgetState.pressed: Colors.transparent,
                WidgetState.hovered: foreground.withValues(alpha: 0.08),
              }),
              side: focusRingStyle(colorScheme, standsOff: isDefault).side,
            ),
      ),
      child: child,
    );
  }
}
