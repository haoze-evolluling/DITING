/// Visibility of the page that owns a context.
///
/// The shell keeps every tab branch mounted (`StatefulShellRoute.indexedStack`), so an offstage
/// page's providers stay watched and their timers keep querying SQLite/Rust behind whatever the
/// user is actually looking at. A page can use [PageVisibilityMixin] to pause its polling while
/// another tab or route is frontmost.
library;

import 'package:flutter/widgets.dart';

/// True when the page owning [context] is the one the user is looking at: its shell branch is not
/// offstage (`TickerMode`) and no other route covers it.
bool isPageVisible(BuildContext context) {
  if (!TickerMode.valuesOf(context).enabled) return false;
  var current = context;
  while (current.mounted) {
    final route = ModalRoute.of(current);
    if (route == null) break;
    if (!route.isCurrent) return false;
    final navigator = route.navigator;
    if (navigator == null) break;
    current = navigator.context;
  }
  return true;
}

/// Drives [onPageVisibilityChanged] as the page moves in and out of view.
mixin PageVisibilityMixin<T extends StatefulWidget> on State<T> {
  bool _visible = false;

  @protected
  bool get pageVisible => _visible;

  /// Implementers attach their pollers when [visible] and detach them when not.
  @protected
  void onPageVisibilityChanged(bool visible);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = isPageVisible(context);
    if (visible == _visible) return;
    _visible = visible;
    onPageVisibilityChanged(visible);
  }
}
