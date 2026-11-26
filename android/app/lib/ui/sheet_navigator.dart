// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:material_ui/material_ui.dart';

class SheetPagesNavigator extends Navigator {
  const SheetPagesNavigator({super.key, super.onGenerateInitialRoutes});
}


NavigatorState sheetNavigatorOf(BuildContext context) {
  var navigator = Navigator.of(context);
  while (true) {
    final outer = navigator.context.findAncestorStateOfType<NavigatorState>();
    if (outer == null) {
      return navigator;
    }
    navigator = outer;
  }
}

final _covers = Expando<ProxyAnimation>();

ProxyAnimation _coverOf(Route<dynamic> route) =>
    _covers[route] ??= ProxyAnimation(kAlwaysDismissedAnimation);

mixin SheetCoverRouteMixin<T> on TransitionRoute<T> {
  ProxyAnimation? _covered;

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    super.didChangePrevious(previousRoute);
    _uncover();
    if (previousRoute != null) {
      _covered = _coverOf(previousRoute)..parent = animation;
    }
  }

  void _uncover() {
    final covered = _covered;
    if (covered != null && covered.parent == animation) {
      covered.parent = kAlwaysDismissedAnimation;
    }
    _covered = null;
  }

  @override
  void dispose() {
    _uncover();
    super.dispose();
  }
}

Animation<double> sheetCoverOf(BuildContext context) {
  var route = ModalRoute.of(context);
  while (route != null) {
    final navigator = route.navigator;
    if (navigator == null || navigator.widget is! SheetPagesNavigator) {
      return _coverOf(route);
    }
    route = ModalRoute.of(navigator.context);
  }
  return kAlwaysDismissedAnimation;
}
