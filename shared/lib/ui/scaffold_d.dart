// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'scaffold.dart';

// Build methods split out of CommonScaffoldState, under the file line cap.
extension CommonScaffoldStateBuild on CommonScaffoldState {
  Widget _buildDockedSearch(AppBarSearchState searchState) {
    final colorScheme = context.colorScheme;
    final glass = LiquidGlassScope.of(context);
    const height = BottomInsetScope.dockedSearchHeight;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final field = ElasticPress(
      child: GooPane(
        child: SearchField(
          height: height,
          controller: _textController,
          focusNode: _searchFocusNode,
          onChanged: searchState.onSearch,
        ),
      ),
    );
    final cancel = TextFieldTapRegion(
      child: TonalButtonTheme(
        size: TonalButtonSize.docked,
        child: _barButton(
          IconButtonData(
            glyph: AppGlyphs.close,
            tooltip: UiLocalizations.of(context).cancel,
            onPressed: _handleCancelDockedSearch,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(
        left: BottomInsetScope.dockedSearchMargin,
        right: BottomInsetScope.dockedSearchMargin,
        bottom: BottomInsetScope.dockedSearchMargin,
      ),
      // A surface of its own, so the list runs under it, not a sheet-wide band.
      child: SafeArea(
        left: false,
        top: false,
        right: false,
        child: GooSurface(
          glass: glass ? LiquidGlassStyle.pill(colorScheme) : null,
          color: SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme),
          shadows: glass ? const [] : dockShadows(colorScheme),
          child: ListenableBuilder(
            listenable: Listenable.merge([_searchFocusNode, _textController]),
            builder: (context, _) {
              final active =
                  _searchFocusNode.hasFocus || _textController.text.isNotEmpty;
              // iOS 27 offers the cancel button while its bottom field is in
              // use, drawn out of the field's end.
              return TweenAnimationBuilder<double>(
                tween: Tween(end: active ? 1 : 0),
                duration: context.motionDuration(_searchSettleDuration),
                curve: _searchCurve,
                builder: (_, t, _) {
                  final grown = math.max(t, 0.0);
                  return SizedBox(
                    height: height,
                    child: Stack(
                      children: [
                        PositionedDirectional(
                          top: 0,
                          end: 0,
                          width: height,
                          height: height,
                          child: ExcludeFocus(
                            excluding: !active,
                            child: ExcludeSemantics(
                              excluding: !active,
                              child: IgnorePointer(
                                ignoring: !active,
                                child: Transform(
                                  alignment: AlignmentDirectional.centerStart,
                                  transform: Matrix4.translationValues(
                                    (rtl ? -1 : 1) * height / 2 * (1 - t),
                                    0,
                                    0,
                                  )..scaleByDouble(grown, grown, 1, 1),
                                  child: Opacity(
                                    opacity: _shownAt(t),
                                    child: cancel,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          top: 0,
                          bottom: 0,
                          start: 0,
                          end: (height + _searchFieldGap) * grown,
                          child: field,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  VoidCallback get _closeSheet =>
      SheetProvider.of(context)?.onClose ?? () => context.safeNestedPop();

  Widget _buildSheetPopButton(
    VoidCallback? backAction, {
    required bool useCloseIcon,
  }) {
    final localizations = UiLocalizations.of(context);
    return AppBarActionButton(
      data: useCloseIcon
          ? IconButtonData(
              glyph: AppGlyphs.close,
              onPressed: _closeSheet,
              tooltip: localizations.close,
            )
          : IconButtonData(
              glyph: AppGlyphs.backFor(Theme.of(context).platform),
              onPressed: backAction ?? () => Navigator.of(context).pop(),
              tooltip: localizations.back,
            ),
    );
  }

  Widget? _buildLeading(VoidCallback? backAction, {required _SheetPop? pop}) {
    final button = _buildLeadingButton(backAction, pop: pop);
    if (button == null) {
      return null;
    }
    final hidden = _sorting;
    return Center(
      child: ExcludeFocus(
        excluding: hidden,
        child: ExcludeSemantics(
          excluding: hidden,
          child: IgnorePointer(
            ignoring: hidden,
            child: AnimatedOpacity(
              opacity: hidden ? 0 : 1,
              duration: context.motionDuration(kThemeAnimationDuration),
              child: ElasticPress(child: button),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildLeadingButton(
    VoidCallback? backAction, {
    required _SheetPop? pop,
  }) {
    if (pop != null) {
      return pop.atFoot
          ? null
          : _buildSheetPopButton(backAction, useCloseIcon: pop.useCloseIcon);
    }
    if (backAction != null) {
      return BackButton(
        onPressed: () {
          if (!mounted) {
            return;
          }
          backAction();
        },
      );
    }
    final route = ModalRoute.of(context);
    if (route?.impliesAppBarDismissal != true) {
      return null;
    }
    return route is PageRoute && route.fullscreenDialog
        ? const CloseButton()
        : const BackButton();
  }

  Widget _buildTitle({required bool compact}) {
    return widget.titleWidget ??
        (widget.titleMenuItems.isEmpty
            ? Text(widget.title!)
            : CommonPopupBox(
                placement: PopupPlacement.overAnchorStart,
                targetBuilder: (open) => _TitleMenuButton(
                  title: widget.title!,
                  compact: compact,
                  onPressed: open,
                ),
                popupBuilder: (_) =>
                    CommonPopupMenu(items: widget.titleMenuItems),
              ));
  }

  List<Widget> _buildActions(
    bool hasSearch,
    IconButtonData? primaryAction,
    _SheetForm form,
  ) {
    if (_sorting) {
      return genActions([
        if (widget.canSort)
          ElasticPress(
            child: AppBarActionButton(
              data: sortModeAction(
                context,
                sorting: true,
                onPressed: _toggleSorting,
              ),
            ),
          ),
      ], edge: AppBarActionEdge.container);
    }
    final lead = hasSearch && !form.hasDockedSearch
        ? IconButtonData(
            glyph: AppGlyphs.search,
            tooltip: UiLocalizations.of(context).search,
            onPressed: _handleToSearch,
          )
        : null;
    final widgets = widget.actions ?? const <Widget>[];
    final selection = _SelectionButtons(widget.selectionActions);
    final atFoot = form.pop?.atFoot == true;
    final fold = _foldBarActions(
      hasLead: lead != null,
      primary: primaryAction,
      icons: [
        if (widget.canSort)
          sortModeAction(context, sorting: false, onPressed: _toggleSorting),
        ...widget.iconActions,
      ],
      confirmation: atFoot ? null : widget.confirmationAction,
      widgetCount: widgets.length + selection.slots,
      menuItems: widget.menuItems,
    );
    final shown = [?lead, ...fold.shown];
    final grouped = shown.length > 1 ? shown.take(_maxGroupedActions) : null;
    final actions = [
      if (grouped != null)
        TonalButtonGroup(
          children: [
            for (final data in grouped)
              identical(data, lead)
                  ? _SearchLead(
                      key: _searchLeadKey,
                      motion: _searchMotion,
                      child: AppBarActionButton(data: data),
                    )
                  : AppBarActionButton(data: data),
          ],
        ),
      for (final data in shown.skip(grouped?.length ?? 0))
        _barButton(
          data,
          icon: identical(data, lead)
              ? _SearchGlyph(
                  motion: _searchMotion,
                  child: GlyphIcon(data.glyph),
                )
              : null,
        ),
      ...selection.build(),
      for (final action in widgets) ElasticPress(child: action),
      if (fold.overflow.isNotEmpty)
        ElasticPress(child: _OverflowMenuButton(items: fold.overflow)),
    ];
    if (lead != null) {
      actions.first = KeyedSubtree(
        key: _searchButtonKey,
        child: _SearchSwell(
          motion: _searchMotion,
          width: (grouped?.length ?? 1) * TonalButtonSize.bar.button,
          slotWidth: grouped == null ? 0 : TonalButtonSize.bar.button,
          droplet: grouped == null ? _searchOrigin : null,
          liftOf: (frame) => frame.glassLift + frame.groupSwell,
          child: actions.first,
        ),
      );
    }
    return genActions(actions, edge: AppBarActionEdge.container);
  }

  Widget _buildBarSearch({required bool fills}) {
    final selection = _SelectionButtons(widget.selectionActions);
    final fold = _foldBarActions(
      hasLead: fills,
      icons: widget.searchActions,
      widgetCount: selection.slots,
    );
    final colorScheme = context.colorScheme;
    final actions = [
      ...selection.build(),
      for (final data in fold.shown) _barButton(data),
      if (fold.overflow.isNotEmpty)
        ElasticPress(child: _OverflowMenuButton(items: fold.overflow)),
    ];
    final buttonCount =
        selection.buttons + fold.shown.length + (fold.overflow.isEmpty ? 0 : 1);
    return _BarSearch(
      motion: _searchMotion,
      opacity: _searchOverBar,
      origin: _searchOrigin,
      fieldKey: _searchFieldKey,
      searching: _isSearch,
      actions: actions,
      actionsWidth:
          buttonCount * TonalButtonSize.bar.button +
          math.max(0, actions.length - 1) * _barButtonGap,
      cancel: fills
          ? _barButton(
              IconButtonData(
                glyph: AppGlyphs.close,
                tooltip: UiLocalizations.of(context).cancel,
                onPressed: _popAppBarLayer,
              ),
            )
          : null,
      glass: LiquidGlassScope.of(context)
          ? LiquidGlassStyle.regular(colorScheme)
          : null,
      color: context.raisedSurfaceLevel.colorOf(colorScheme),
      // The field's own buttons stay off the bar's button fills and glass.
      field: IconButtonTheme(
        data: IconButtonTheme.of(context),
        child: SearchField(
          autofocus: true,
          controller: _textController,
          focusNode: _searchFocusNode,
          onChanged: (value) => _appBarState.value.searchState?.onSearch(value),
        ),
      ),
    );
  }

  Widget _buildFootActions(IconButtonData confirmation) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: AlertActions(
        actions: [
          TextButton(
            onPressed: _closeSheet,
            child: Text(UiLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: confirmation.isLoading ? null : confirmation.onPressed,
            child: confirmation.isLoading
                ? CommonCircleLoading(size: TonalButtonSize.bar.icon)
                : Text(confirmation.tooltip!),
          ),
        ],
      ),
    );
  }

}
