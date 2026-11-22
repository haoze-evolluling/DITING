// Portions derived from FlClash (https://github.com/chen08209/FlClash), Copyright (c) the FlClash authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/navigator.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

Page<void> androidDefaultPage(GoRouterState state, Widget child) {
  return DefaultPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    child: child,
  );
}

class DefaultPage<T> extends Page<T> {
  const DefaultPage({required this.child, super.key, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    Widget builder(BuildContext _) => child;
    return context.isMobileView
        ? CardPageRoute<T>(settings: this, builder: builder)
        : FadePageRoute<T>(settings: this, builder: builder);
  }
}

class RootShellPage<T> extends RootPage<T> {
  const RootShellPage({required super.child, super.key, super.name});
}
