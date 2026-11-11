/// Expanded floating log window: header (drag strip), search, status chips and the live list.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/overlay/floating_log_data.dart';
import 'package:diting_android/overlay/floating_log_main.dart';
import 'package:diting_android/overlay/floating_log_rows.dart';
import 'package:diting_android/pages/observability/requests_page.dart'
    show requestStatusStyle;
import 'package:diting_android/state/observability_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class FloatingLogPanel extends StatefulWidget {
  const FloatingLogPanel({
    super.key,
    required this.source,
    required this.window,
    required this.sizeIndex,
    required this.onResize,
    required this.onCollapse,
  });

  /// Height of the header; the native side treats it as the drag strip.
  static const double headerHeight = 48;

  final FloatingLogSource source;
  final FloatingLogWindowChannel window;
  final int sizeIndex;
  final ValueChanged<int> onResize;
  final VoidCallback onCollapse;

  @override
  State<FloatingLogPanel> createState() => _FloatingLogPanelState();
}

class _FloatingLogPanelState extends State<FloatingLogPanel> {
  static const _refreshInterval = Duration(seconds: 2);
  static const _searchDebounce = Duration(milliseconds: 250);

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();

  FloatingLogSnapshot? _snapshot;
  RequestStatus _status = RequestStatus.all;
  RequestSource _source = RequestSource.all;
  String _query = '';
  bool _paused = false;
  bool _searching = false;
  bool _loading = false;

  /// "Clear" hides rows up to this time; the database is never touched.
  int _clearedAt = 0;
  String? _expandedKey;
  String? _toast;

  /// Rows that arrived while the list was scrolled away from the top.
  int _unseen = 0;
  Timer? _refreshTimer;
  Timer? _searchTimer;
  Timer? _toastTimer;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onFocusChange);
    _scroll.addListener(_onScroll);
    widget.window.onBack(_onBack);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _load();
    _startRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchTimer?.cancel();
    _toastTimer?.cancel();
    _lifecycle?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefresh();
      _load();
    } else {
      _refreshTimer?.cancel();
    }
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    if (_paused) return;
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _load());
  }

  void _onFocusChange() {
    // The window takes focus only while typing, so the keyboard can open without the overlay
    // swallowing the back key and input of the app underneath the rest of the time.
    unawaited(widget.window.setFocusable(_searchFocus.hasFocus));
  }

  void _onBack() {
    if (_searchFocus.hasFocus) _searchFocus.unfocus();
  }

  void _onScroll() {
    if (_unseen > 0 && _scroll.hasClients && _scroll.offset <= 8) {
      setState(() => _unseen = 0);
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final previous = _snapshot?.items.firstOrNull?.timestamp;
      final next = await widget.source.load(query: _query, source: _source);
      if (!mounted) return;
      final atTop = !_scroll.hasClients || _scroll.offset <= 8;
      setState(() {
        if (!atTop && previous != null) {
          _unseen += next.items
              .where((item) => item.timestamp > previous)
              .length;
        }
        _snapshot = next;
      });
    } finally {
      _loading = false;
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _refreshTimer?.cancel();
    } else {
      _load();
      _startRefresh();
    }
  }

  void _clear() {
    setState(() {
      _clearedAt = DateTime.now().millisecondsSinceEpoch;
      _expandedKey = null;
      _unseen = 0;
    });
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      _searchFocus.requestFocus();
    } else {
      _searchFocus.unfocus();
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
        _onSearch('');
      }
    }
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      _query = value.trim();
      _load();
    });
  }

  void _setSource(RequestSource source) {
    if (source == _source) return;
    setState(() => _source = source);
    _load();
  }

  Future<void> _copy(String text) async {
    final message = context.l10n.floatingLogCopied;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _showToast(message);
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    setState(() => _unseen = 0);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final visible = [
      for (final item in _snapshot?.items ?? const <ObservedRequest>[])
        if (item.timestamp > _clearedAt) item,
    ];
    final counts = floatingLogCounts(visible);
    final rows = _status == RequestStatus.all
        ? visible
        : [
            for (final item in visible)
              if (item.status == _status) item,
          ];
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme),
        shape: AppShape.xl.copyWith(
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SurfaceScope(
          level: SurfaceLevel.floatingOf(colorScheme),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  if (_searching) _searchBar(context),
                  _chips(context, counts),
                  Expanded(child: _list(context, rows, visible.isEmpty)),
                  _footer(context, rows.length),
                ],
              ),
              if (_unseen > 0)
                FloatingLogNewRowsPill(count: _unseen, onTap: _scrollToTop),
              if (_toast case final message?)
                FloatingLogToast(message: message),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return SizedBox(
      height: FloatingLogPanel.headerHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(
          children: [
            // Live state at a glance: a filled dot while polling, hollow while paused.
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _paused ? Colors.transparent : colorScheme.success,
                border: Border.all(
                  color: _paused ? colorScheme.outline : colorScheme.success,
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _paused ? l10n.floatingLogPaused : l10n.floatingLogTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.headline
                    .of(context)
                    .copyWith(color: colorScheme.onSurface),
              ),
            ),
            _iconButton(
              glyph: AppGlyphs.search,
              tooltip: l10n.floatingLogSearch,
              selected: _searching,
              onPressed: _toggleSearch,
            ),
            _iconButton(
              glyph: AppGlyphs.playPause(_paused ? 0 : 1),
              tooltip: _paused ? l10n.floatingLogResume : l10n.floatingLogPause,
              onPressed: _togglePause,
            ),
            CommonPopupBox(
              targetBuilder: (open) => _iconButton(
                glyph: AppGlyphs.more,
                tooltip: UiLocalizations.of(context).more,
                onPressed: open,
              ),
              popupBuilder: (_) =>
                  CommonPopupMenu(dense: true, items: _menuItems(context)),
            ),
            _iconButton(
              glyph: AppGlyphs.remove,
              tooltip: l10n.floatingLogMinimize,
              onPressed: widget.onCollapse,
            ),
          ],
        ),
      ),
    );
  }

  List<CommonPopupMenuItem> _menuItems(BuildContext context) {
    final l10n = context.l10n;
    final sizeLabels = [
      l10n.floatingLogSizeSmall,
      l10n.floatingLogSizeMedium,
      l10n.floatingLogSizeLarge,
    ];
    return [
      CommonPopupMenuItem(
        label: l10n.obsSource,
        glyph: AppGlyphs.filter,
        subItems: [
          for (final source in RequestSource.values)
            CommonPopupMenuItem(
              label: source.label,
              checked: source == _source,
              onPressed: () => _setSource(source),
            ),
        ],
      ),
      CommonPopupMenuItem(
        label: l10n.floatingLogPanelSize,
        glyph: AppGlyphs.layers,
        subItems: [
          for (var i = 0; i < sizeLabels.length; i++)
            CommonPopupMenuItem(
              label: sizeLabels[i],
              checked: i == widget.sizeIndex,
              onPressed: () => widget.onResize(i),
            ),
        ],
      ),
      CommonPopupMenuItem(
        label: l10n.floatingLogClear,
        glyph: AppGlyphs.clearAll,
        onPressed: _clear,
      ),
      CommonPopupMenuItem(
        label: l10n.floatingLogOpenApp,
        glyph: AppGlyphs.openExternal,
        section: const CommonPopupMenuSection(),
        onPressed: widget.window.openApp,
      ),
      CommonPopupMenuItem(
        label: l10n.floatingLogHide,
        subtitle: l10n.floatingLogHideHint,
        glyph: AppGlyphs.eyeOff,
        danger: true,
        onPressed: widget.window.dismiss,
      ),
    ];
  }

  Widget _iconButton({
    required Glyph glyph,
    required String tooltip,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    final colorScheme = context.colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: selected ? colorScheme.secondaryContainer : null,
        foregroundColor: selected
            ? colorScheme.onSecondaryContainer
            : colorScheme.onSurfaceVariant,
      ),
      icon: GlyphIcon(glyph, size: 20),
    );
  }

  Widget _searchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: SearchField(
        controller: _searchController,
        focusNode: _searchFocus,
        height: 36,
        hintText: context.l10n.floatingLogSearchHint,
        onChanged: _onSearch,
        onSubmitted: _searchFocus.unfocus,
      ),
    );
  }

  Widget _chips(BuildContext context, Map<RequestStatus, int> counts) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        itemCount: floatingLogStatuses.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final status = floatingLogStatuses[index];
          return FloatingLogFilterChip(
            label: status.label,
            count: counts[status] ?? 0,
            selected: status == _status,
            color: status == RequestStatus.all
                ? null
                : requestStatusStyle(context, status).$1,
            onTap: () => setState(() {
              _status = status;
              _expandedKey = null;
            }),
          );
        },
      ),
    );
  }

  Widget _list(BuildContext context, List<ObservedRequest> rows, bool none) {
    final l10n = context.l10n;
    final snapshot = _snapshot;
    if (snapshot == null) {
      // The first read takes a few milliseconds; a spinner would only flash.
      return const SizedBox.shrink();
    }
    if (rows.isEmpty) {
      final String title;
      final String body;
      if (!snapshot.available) {
        title = l10n.floatingLogUnavailable;
        body = l10n.floatingLogUnavailableBody;
      } else if (none && _query.isEmpty) {
        title = l10n.floatingLogEmpty;
        body = _clearedAt > 0
            ? l10n.floatingLogClearedBody
            : l10n.floatingLogEmptyBody;
      } else {
        title = l10n.obsNoMatchingRequests;
        body = l10n.floatingLogNoMatchBody;
      }
      return FloatingLogEmptyState(title: title, body: body);
    }
    return PrismListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      itemCount: rows.length,
      estimatedItemExtent: 64,
      itemBuilder: (context, index) {
        final request = rows[index];
        return MemoBuilder(
          key: ValueKey(request.key),
          inputs: [request, request.key == _expandedKey],
          builder: (_) => FloatingLogRow(
            request: request,
            expanded: request.key == _expandedKey,
            onTap: () => setState(() {
              _expandedKey = _expandedKey == request.key ? null : request.key;
            }),
            onCopy: _copy,
          ),
        );
      },
    );
  }

  Widget _footer(BuildContext context, int shown) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final parts = [
      l10n.floatingLogShown(shown),
      if (_source != RequestSource.all) _source.label,
      if (_query.isNotEmpty) '“$_query”',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          parts.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
