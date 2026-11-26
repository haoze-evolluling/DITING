// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:async';

import 'package:diting_shared/ui/navigator.dart';
import 'package:flutter/widgets.dart';


ScrollCacheExtent? arrivalScrollCacheExtent(bool routeSettled) {
  return routeSettled ? null : const ScrollCacheExtent.pixels(0);
}

class RouteArrivalScope extends StatefulWidget {
  const RouteArrivalScope({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollCacheExtent? cacheExtent)
  builder;

  @override
  State<RouteArrivalScope> createState() => _RouteArrivalScopeState();
}

class _RouteArrivalScopeState extends State<RouteArrivalScope> {
  bool? _settled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled != null) {
      return;
    }
    _settled = !isRouteArriving(context);
    if (!_settled!) {
      unawaited(_settle());
    }
  }

  Future<void> _settle() async {
    await whenRouteSettled(context);
    if (mounted) {
      setState(() => _settled = true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, arrivalScrollCacheExtent(_settled ?? true));
}
