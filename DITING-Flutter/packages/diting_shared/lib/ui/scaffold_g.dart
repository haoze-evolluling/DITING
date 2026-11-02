// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'scaffold.dart';

// App bar builders split out of CommonScaffoldState, under the file line cap.

extension CommonScaffoldStateAppBar on CommonScaffoldState {
  Widget _buildAppBarWrap(Widget appBar, {required bool barSearch}) {
    return TonalButtonTheme(
      glass: LiquidGlassScope.of(context),
      child: Stack(
        key: _barKey,
        fit: StackFit.passthrough,
        children: [
          appBar,
          if (barSearch)
            Positioned.fill(child: _buildBarSearch(fills: _searchFillsBar)),
          if (_isSearch || _sorting)
            BackLayerScope(
              onBack: _handleExitAppBarLayer,
              child: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _buildFloatingHeader(Widget appBar) {
    final top = MediaQuery.paddingOf(context).top;
    return FloatingHeader(
      backgroundColor:
          widget.backgroundColor ??
          SurfaceLevel.page.colorOf(context.colorScheme),
      fadeStart: top / (top + pageToolbarHeight),
      overhang: _headerOverhang,
      child: appBar,
    );
  }

  PreferredSizeWidget _buildAppBar(VoidCallback? backAction, _SheetForm form) {
    final isCompact = form.isCompact;
    final isMobileView = ViewScope.isMobileOf(context);
    final pushed =
        form.pop == null &&
        widget.titleWidget == null &&
        isMobileView &&
        ModalRoute.of(context)?.impliesAppBarDismissal == true;
    final compactTitle = isCompact || pushed;
    final titleEndInset = appBarActionInset(
      _isCompactBar(context, isMobileView),
    );
    // Under a sheet the bar drops its actions, so none reads as the sheet's.
    final uncovered = ReverseAnimation(sheetCoverOf(context));
    return PreferredSize(
      preferredSize: Size.fromHeight(
        isCompact ? sheetToolbarHeight : pageToolbarHeight,
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([_appBarState, _searchCovered]),
            builder: (_, _) {
              final state = _appBarState.value;
              final leading = _buildLeading(backAction, pop: form.pop);
              final barSearch =
                  state.searchState != null && !form.hasDockedSearch;
              final covered = barSearch && _searchCovered.value;
              final hidesBar = covered && _searchFillsBar;
              Widget underSearch(Widget child, Animation<double> opacity) =>
                  barSearch
                  ? _UnderBarSearch(
                      opacity: opacity,
                      searching: _isSearch,
                      child: child,
                    )
                  : child;
              Widget? underField(Widget? child, Animation<double> opacity) =>
                  child == null || !_searchFillsBar
                  ? child
                  : underSearch(child, opacity);
              final searchLeading =
                  barSearch && _searchFillsBar && leading != null
                  ? KeyedSubtree(
                      key: _searchLeadingKey,
                      child: _SearchSwell(
                        motion: _searchMotion,
                        width: TonalButtonSize.bar.button,
                        liftOf: (frame) => frame.glassLift,
                        child: leading,
                      ),
                    )
                  : leading;
              final appBar = AppBar(
                clipBehavior: Clip.none,
                automaticallyImplyLeading: false,
                animateColor: true,
                forceMaterialTransparency: true,
                toolbarHeight: isCompact ? sheetToolbarHeight : null,
                centerTitle: isCompact,
                titleTextStyle: compactTitle
                    ? AppTextStyle.headline.of(context)
                    : AppTextStyle.pageTitle.of(context),
                leading: hidesBar
                    ? null
                    : underField(searchLeading, _leadingUnderSearch),
                // The leading slot already trails its button by a margin.
                titleSpacing: leading == null ? null : 0,
                title: hidesBar
                    ? null
                    : underField(
                        leading == null || isCompact
                            ? _buildTitle(compact: compactTitle)
                            : Padding(
                                padding: EdgeInsetsDirectional.only(
                                  end: titleEndInset,
                                ),
                                child: _buildTitle(compact: compactTitle),
                              ),
                        _titleUnderSearch,
                      ),
                actions: [
                  if (!covered)
                    for (final action in _buildActions(
                      state.searchState != null,
                      widget.primaryAction,
                      form,
                    ))
                      FadeTransition(
                        opacity: uncovered,
                        child: underSearch(
                          action,
                          action.key == _searchButtonKey
                              ? _leadUnderSearch
                              : _actionsUnderSearch,
                        ),
                      ),
                ],
              );
              final bar = _buildAppBarWrap(appBar, barSearch: barSearch);
              return isCompact
                  ? bar
                  : _buildFloatingHeader(_WindowControlsClearance(child: bar));
            },
          ),
          ValueListenableBuilder(
            valueListenable: _loadingNotifier,
            builder: (_, value, _) {
              return value == true
                  ? const LinearProgressIndicator()
                  : Container();
            },
          ),
        ],
      ),
    );
  }
}
