library;

import 'package:flutter/widgets.dart';

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

mixin PageVisibilityMixin<T extends StatefulWidget> on State<T> {
  bool _visible = false;

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
