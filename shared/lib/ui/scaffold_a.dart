// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'scaffold.dart';

class CommonScaffoldState extends State<CommonScaffold>
    with SingleTickerProviderStateMixin {
  late final ValueNotifier<AppBarState> _appBarState;
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier(false);
  final ValueNotifier<List<String>> _keywordsNotifier = ValueNotifier([]);
  final _textController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final _searchMotion = _SearchMotion(this);
  late final Animation<double> _titleUnderSearch = _searchMotion.drive(
    (frame) => frame.titleOpacity,
  );
  late final Animation<double> _actionsUnderSearch = _searchMotion.drive(
    (frame) => frame.actionsOpacity,
  );
  late final Animation<double> _searchOverBar = _searchMotion.drive(
    (frame) => frame.fieldOpacity,
  );
  late final Animation<double> _leadingUnderSearch = _searchMotion.drive(
    (frame) => frame.leadingOpacity,
  );
  late final Animation<double> _leadUnderSearch = _searchMotion.drive(
    (frame) => frame.leadOpacity,
  );
  final _searchOrigin = ValueNotifier<_SearchOrigin?>(null);
  final _searchCovered = ValueNotifier(false);
  final _searchButtonKey = GlobalKey();
  final _searchLeadKey = GlobalKey();
  final _searchLeadingKey = GlobalKey();
  final _searchFieldKey = GlobalKey();
  final _barKey = GlobalKey();
  var _searchFillsBar = true;
  var _searchDocked = false;
  var _sorting = false;

  bool get _isSearch {
    return _appBarState.value.searchState?.query != null;
  }

  @override
  void initState() {
    super.initState();
    _appBarState = ValueNotifier(AppBarState(searchState: widget.searchState));
    _loadingNotifier.value = widget.isLoading;
    _searchFocusNode.addListener(_handleSearchFocusChange);
    _searchMotion.addStatusListener((status) {
      if (!status.isAnimating) {
        _searchCovered.value = _isSearch;
      }
    });
    HardwareKeyboard.instance.addHandler(_handleSearchShortcut);
  }

  Future<void> _updateSearchState(AppBarSearchStateBuilder builder) async {
    _appBarState.value = _appBarState.value.copyWith(
      searchState: builder(_appBarState.value.searchState),
    );
  }

  void _handleToSearch() {
    _searchOrigin.value = _measureSearchOrigin();
    _updateSearchState((state) => state?.copyWith(query: ''));
    _moveSearch(open: true);
  }

  Rect? _measureInBar(GlobalKey key) {
    final bar = _barKey.currentContext?.findRenderObject();
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || bar is! RenderBox || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: bar) & box.size;
  }

  _SearchOrigin? _measureSearchOrigin() {
    final group = _measureInBar(_searchButtonKey);
    return group == null
        ? null
        : _SearchOrigin.of(
            group,
            lead: _measureInBar(_searchLeadKey),
            leading: _measureInBar(_searchLeadingKey),
          );
  }

  void _moveSearch({required bool open}) {
    _searchCovered.value = false;
    if (context.disableAnimations) {
      _searchMotion.jumpTo(open: open);
      _searchCovered.value = _isSearch;
      return;
    }
    final origin = _searchOrigin.value;
    _searchMotion.moveTo(
      open: open,
      returns: origin == null || !origin.lone
          ? _SearchReturn.group
          : !_searchFillsBar
          ? _SearchReturn.morph
          : origin.leading == null
          ? _SearchReturn.droplet
          : _SearchReturn.pinch,
    );
  }

  // A bar's field at its end folds back once left empty, as a toolbar search
  // field does on macOS; one across the bar waits for its cancel button.
  void _handleSearchFocusChange() {
    if (_searchFocusNode.hasFocus ||
        _searchFillsBar ||
        _textController.text.isNotEmpty) {
      return;
    }
    handleExitSearching();
  }

  void _toggleSorting() {
    setState(() {
      _sorting = !_sorting;
    });
  }

  bool _handleSearchShortcut(KeyEvent event) {
    if (event is! KeyDownEvent ||
        _appBarState.value.searchState == null ||
        _sorting ||
        !controlSingleActivator(LogicalKeyboardKey.keyF)
            .accepts(event, HardwareKeyboard.instance) ||
        !_isFrontmost) {
      return false;
    }
    if (_isSearch || _searchDocked) {
      _searchFocusNode.requestFocus();
      _textController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _textController.text.length,
      );
    } else {
      _handleToSearch();
    }
    return true;
  }

  // Kept-alive pages and pages under another route stay mounted too.
  bool get _isFrontmost {
    if (!mounted ||
        context.getInheritedWidgetOfExactType<PageActivityScope>()?.isActive ==
            false) {
      return false;
    }
    BuildContext? current = context;
    while (current != null && current.mounted) {
      final route = ModalRoute.of(current);
      if (route == null) {
        return true;
      }
      if (!route.isCurrent) {
        return false;
      }
      current = route.navigator?.context;
    }
    return true;
  }

  @override
  void didUpdateWidget(CommonScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchState != widget.searchState) {
      final query = _appBarState.value.searchState?.query;
      _appBarState.value = _appBarState.value.copyWith(
        searchState: widget.searchState?.copyWith(query: query),
      );
      if (widget.searchState == null) {
        _searchMotion.jumpTo(open: false);
        _searchCovered.value = false;
      }
    }
    if (oldWidget.isLoading != widget.isLoading) {
      _loadingNotifier.value = widget.isLoading;
    }
    if (oldWidget.canSort && !widget.canSort) {
      _sorting = false;
    }
  }

  void _handleClearInput() {
    _textController.text = '';
    if (_appBarState.value.searchState != null) {
      _appBarState.value.searchState!.onSearch('');
    }
  }

  void handleExitSearching() {
    if (!_isSearch) {
      return;
    }
    final field = _measureInBar(_searchFieldKey);
    _searchOrigin.value = _searchOrigin.value?.withField(field);
    _handleClearInput();
    _searchFocusNode.unfocus();
    _updateSearchState((state) => state?.copyWith(query: null));
    _moveSearch(open: false);
    // The covered bar, search button included, returns with the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchOrigin.value =
            _measureSearchOrigin()?.withField(field) ?? _searchOrigin.value;
      }
    });
  }

  void _handleCancelDockedSearch() {
    _handleClearInput();
    _searchFocusNode.unfocus();
  }

  void _handleExitAppBarLayer() {
    handleExitSearching();
    if (_sorting) {
      _toggleSorting();
    }
  }

  void _popAppBarLayer() {
    if (!_isSearch) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleSearchShortcut);
    _appBarState.dispose();
    _textController.dispose();
    _searchFocusNode.dispose();
    _searchMotion.dispose();
    _searchOrigin.dispose();
    _searchCovered.dispose();
    _loadingNotifier.dispose();
    _keywordsNotifier.dispose();
    super.dispose();
  }

  void addKeyword(String keyword) {
    final isContains = _keywordsNotifier.value.contains(keyword);
    if (isContains) return;
    _setKeywords(List<String>.from(_keywordsNotifier.value)..add(keyword));
  }

  void _deleteKeyword(String keyword) {
    final isContains = _keywordsNotifier.value.contains(keyword);
    if (!isContains) return;
    _setKeywords(List<String>.from(_keywordsNotifier.value)..remove(keyword));
  }

  void _setKeywords(List<String> keywords) {
    _keywordsNotifier.value = keywords;
    widget.onKeywordsUpdate?.call(keywords);
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.title != null || widget.titleWidget != null);
    final backAction = widget.backAction;
    final form = _SheetForm.of(
      context,
      searchState: widget.searchState,
      searchInBar: widget.searchInBar,
      hasConfirmationAction: widget.confirmationAction != null,
    );
    final isCompact = form.isCompact;
    _searchFillsBar = _isCompactBar(context, ViewScope.isMobileOf(context));
    _searchDocked = form.hasDockedSearch;
    final bottomInset = BottomInsetScope.of(context);
    // A detent sheet fills the height its detent gives it and clips its own
    // corners; any other bottom sheet sizes to its content and brings both.
    final hugsContent = isCompact && !SheetOverhangScope.fillsDetentOf(context);
    // The page's bar floats over its body, which leaves the bar's height at
    // its top through MediaQuery padding, as extendBodyBehindAppBar does.
    final barFloats = !isCompact;
    final sortableBody = SortModeScope(sorting: _sorting, child: widget.body);
    final body = SafeArea(
      top: !barFloats,
      bottom: false,
      child: ValueListenableBuilder(
        valueListenable: _keywordsNotifier,
        builder: (context, keywords, _) {
          final hasKeywords = keywords.isNotEmpty;
          final barInset = MediaQuery.paddingOf(context).top;
          final overlap = barFloats
              ? barInset
              : isCompact
              ? sheetAppBarHeight
              : 0.0;
          // A wrapper toggled with the strip would remount the body.
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: hugsContent ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (hasKeywords)
                Padding(
                  padding: EdgeInsets.only(top: overlap + 4, bottom: 16),
                  child: _KeywordStrip(
                    keywords: keywords,
                    onDeleted: _deleteKeyword,
                  ),
                ),
              Flexible(
                fit: hugsContent ? FlexFit.loose : FlexFit.tight,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: hasKeywords,
                  child: FloatingBarScope(
                    inset: hasKeywords ? 0 : overlap,
                    child: sortableBody,
                  ),
                ),
              ),
            ],
          );
          return TopInsetScope(
            inset: hasKeywords ? 0 : TopInsetScope.of(context) ?? 0,
            child: FloatingBarScope(
              inset: overlap,
              child: overlap > 0
                  ? _FocusClearOfBar(inset: overlap, child: content)
                  : content,
            ),
          );
        },
      ),
    );
    final appBar = _buildAppBar(backAction, form);
    final content = form.hasDockedSearch
        ? BottomInsetScope(
            inset: bottomInset + BottomInsetScope.dockedSearchInset,
            child: body,
          )
        : body;
    if (!isCompact) {
      final docked = form.dockedSearch;
      return AppBarInsetScope(
        child: Scaffold(
          appBar: appBar,
          extendBodyBehindAppBar: barFloats,
          body: _BodyScope(
            child: docked == null
                ? content
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      content,
                      if (!_sorting)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: _buildDockedSearch(docked),
                        ),
                    ],
                  ),
          ),
          resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
          backgroundColor: widget.backgroundColor,
        ),
      );
    }
    final sheetBody = FloatingHeaderBody(
      backgroundColor:
          widget.backgroundColor ??
          SurfaceLevel.page.colorOf(context.colorScheme),
      header: SheetToolBar(appBar: appBar, dragHandle: form.hasDragHandle),
      footer: form.dockedSearch == null || _sorting
          ? null
          : _buildDockedSearch(form.dockedSearch!),
      body: content,
    );
    final footed = form.pop?.atFoot == true
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: hugsContent ? FlexFit.loose : FlexFit.tight,
                child: sheetBody,
              ),
              _buildFootActions(widget.confirmationAction!),
            ],
          )
        : sheetBody;
    if (!hugsContent) {
      return AppBarInsetScope(
        child: Scaffold(
          body: footed,
          resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
          backgroundColor: widget.backgroundColor,
        ),
      );
    }
    final hugging = Column(
      mainAxisSize: MainAxisSize.min,
      children: [Flexible(child: footed)],
    );
    return AppBarInsetScope(
      child: form.hasDragHandle
          ? ClipRSuperellipse(
              borderRadius: AppRadius.top(AppCorner.xxl),
              child: hugging,
            )
          : hugging,
    );
  }
}
