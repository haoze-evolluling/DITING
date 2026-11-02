// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'popup.dart';

// Build methods split out of _CommonPopupMenuState to stay under the file line cap.
const _headerIndex = -1;
const _levelWidthScale = 1.12;
const _levelScaleStep = 0.05;
const _levelFadeStep = 0.2;
const _levelShadowStep = 1 / 3;
const _minShadow = 1 / 6;
const _widthSpan = 0.3;
const _glassSpan = _Span(0, 0.35);
final _arrowTurns = const _Span(0, 1).chain(Tween(begin: 0.0, end: 0.25));
final _labelWidths = <(String, TextStyle, TextScaler, bool), double>{};

extension _CommonPopupMenuStateBuild on _CommonPopupMenuState {
  EdgeInsets _rowPadding({required bool arrow}) => widget.dense
      ? (arrow ? _denseItemArrowPadding : _denseItemPadding)
      : (arrow ? _itemArrowPadding : _itemPadding);

  double get _iconSize => widget.dense ? _denseItemIconSize : _itemIconSize;

  AppTextStyle get _labelStyle =>
      widget.dense ? AppTextStyle.footnote : AppTextStyle.subheadline;

  double get _minWidth => widget.dense ? _denseMenuMinWidth : _menuMinWidth;

  double get _maxWidth => widget.dense ? _denseMenuMaxWidth : _menuMaxWidth;

  Widget _buildRow(
    BuildContext context, {
    required CommonPopupMenuItem item,
    required int index,
    required VoidCallback? onTap,
    bool pressed = false,
    Animation<double>? arrowTurns,
  }) {
    final colorScheme = context.colorScheme;
    final enabled = onTap != null;
    final color = item.danger ? colorScheme.error : colorScheme.onSurface;
    final foregroundColor = enabled ? color : color.opacity30;
    final dense = widget.dense;
    Widget? arrow;
    if (item.subItems.isNotEmpty) {
      arrow = GlyphIcon(
        AppGlyphs.chevronForward,
        size: _submenuArrowSize,
        color: foregroundColor,
      );
      if (arrowTurns != null) {
        arrow = RotationTransition(turns: arrowTurns, child: arrow);
      }
    } else if (item.checked == true) {
      arrow = GlyphIcon(
        AppGlyphs.check,
        size: _submenuArrowSize,
        color: foregroundColor,
      );
    }
    // A press is the menu's to follow across the rows, so the row's ink shows hover and focus only.
    final child = InkWell(
      customBorder: AppShape.all(_itemRadius),
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: item.danger ? colorScheme.error.opacity10 : null,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: pressed ? Theme.of(context).highlightColor : null,
          shape: AppShape.all(_itemRadius),
        ),
        child: Padding(
          padding: _rowPadding(arrow: arrow != null),
          child: Row(
            children: [
              if (item.glyph case final glyph?) ...[
                GlyphIcon(glyph, size: _iconSize, color: foregroundColor),
                SizedBox(width: dense ? 10 : 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EmojiText(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _labelStyle
                          .of(context)
                          .copyWith(color: foregroundColor),
                    ),
                    if (item.subtitle case final subtitle?)
                      EmojiText(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (dense
                                    ? AppTextStyle.caption1
                                    : AppTextStyle.footnote)
                                .of(context)
                                .copyWith(
                                  color: enabled
                                      ? colorScheme.onSurfaceVariant
                                      : colorScheme.onSurfaceVariant.opacity30,
                                ),
                      ),
                  ],
                ),
              ),
              if (arrow != null) ...[const SizedBox(width: 8), arrow],
            ],
          ),
        ),
      ),
    );
    return MetaData(
      metaData: _MenuRow(
        index,
        onTap,
        togglesSubMenu:
            item.subItems.isNotEmpty && !(index == _headerIndex && _folding),
      ),
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        enabled: enabled,
        checked: item.checked,
        child: child,
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    CommonPopupMenuItem item,
    int index, {
    required bool active,
  }) {
    final pressed = active && _pressed == index;
    if (item.subItems.isNotEmpty) {
      return Builder(
        builder: (itemContext) => _buildRow(
          itemContext,
          item: item,
          index: index,
          pressed: pressed,
          onTap: () => _push(itemContext, index),
        ),
      );
    }
    final onPressed = item.onPressed;
    return _buildRow(
      context,
      item: item,
      index: index,
      pressed: pressed,
      onTap: onPressed == null ? null : () => _select(onPressed),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Semantics(
        header: true,
        child: EmojiText(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    _MenuLevel level, {
    required bool active,
    required int? covered,
  }) {
    final owner = level.owner;
    final checked = owner == null
        ? level.items.indexWhere((item) => item.checked == true)
        : -1;
    final items = [
      for (var index = 0; index < level.items.length; index++) ...[
        if (level.items[index].section case final section?) ...[
          if (index > 0) const Divider(height: _dividerHeight, thickness: 1),
          if (section.title case final title?)
            _buildSectionTitle(context, title),
        ],
        // The item a sub menu stands on hides under its header, which redraws it.
        Opacity(
          key: index == checked ? _checkedKey : null,
          opacity: index == covered ? 0 : 1,
          child: _buildItem(context, level.items[index], index, active: active),
        ),
      ],
    ];
    if (owner == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRow(
          context,
          item: owner,
          index: _headerIndex,
          pressed: active && _pressed == _headerIndex,
          onTap: _toggleTop,
          arrowTurns: active ? _arrow : const AlwaysStoppedAnimation(0.25),
        ),
        IgnorePointer(
          ignoring: active && _folding,
          child: FadeTransition(
            opacity: active ? _items : kAlwaysCompleteAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: _dividerHeight, thickness: 1),
                ...items,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLevel(
    BuildContext context,
    _MenuLevel level, {
    required GlobalKey cardKey,
    required int depth,
    required double pivot,
    required int? covered,
  }) {
    final receding = depth > 0;
    final step = receding ? null : level.step;
    final colorScheme = context.colorScheme;
    final glass = LiquidGlassScope.of(context)
        ? LiquidGlassStyle.menu(colorScheme)
        : null;
    final rim = glass == null ? null : LiquidGlassRim.menu(colorScheme);
    final fill = SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme);
    // A card behind a sub menu takes a tap as one outside that sub menu.
    return GestureDetector(
      excludeFromSemantics: true,
      onTap: receding ? _pop : null,
      child: ExcludeSemantics(
        excluding: receding,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, child) {
              final unfold = _unfold.value;
              final settled = unfold.clamp(0.0, 1.0);
              final width = step == null
                  ? 1.0
                  : (settled / _widthSpan).clamp(0.0, 1.0);
              final distance = receding ? depth - 1 + settled : 0.0;
              final scale = math.max(0.0, 1 - _levelScaleStep * distance);
              final shadow = receding
                  ? math.max(_minShadow, 1 - distance * _levelShadowStep)
                  : step == null
                  ? 1.0
                  : settled;
              return Transform(
                transform: Matrix4.diagonal3Values(scale, scale, 1),
                alignment: Alignment.topRight,
                origin: Offset(0, pivot),
                child: PopupMenuCard(
                  key: cardKey,
                  grow: step == null ? 1 : unfold,
                  origin: step == null
                      ? null
                      : (
                          top: step.itemTop - level.top,
                          height: step.itemHeight,
                        ),
                  shadows: glass == null
                      ? _cardShadows(colorScheme, shadow)
                      : glassMenuShadows(colorScheme, shadow),
                  fill: fill,
                  dim: colorScheme.surface.withValues(
                    alpha: math.min(0.4, _levelFadeStep * distance),
                  ),
                  glass: step == null
                      ? glass
                      : glass?.scale(_glassSpan.transform(unfold)),
                  rim: step == null
                      ? rim
                      : rim?.scale(_glassSpan.transform(unfold)),
                  bare: _platter?.value ?? false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: lerpDouble(
                        level.fromWidth,
                        level.minWidth,
                        width,
                      )!,
                      maxWidth: lerpDouble(
                        level.fromWidth,
                        level.maxWidth,
                        width,
                      )!,
                      maxHeight: _maxHeightOf(context, level),
                    ),
                    child: child,
                  ),
                ),
              );
            },
            child: IgnorePointer(
              ignoring: receding,
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.all(_cardInset),
                  child: _buildsLazily(level)
                      ? _buildLazyContent(context, level)
                      : SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: IntrinsicWidth(
                            child: _buildContent(
                              context,
                              level,
                              active: !receding,
                              covered: covered,
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
  }
}
