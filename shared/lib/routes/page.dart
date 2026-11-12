// Portions derived from FlClash (https://github.com/chen08209/FlClash), Copyright (c) the FlClash authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/navigator.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Wraps a sub page in a [Page] whose route supplies FlClash's transition: a
/// horizontal card slide on mobile, a plain fade on desktop. Every route must
/// use `pageBuilder`: go_router only falls back to a theme transition for
/// `builder` when the app is a `MaterialApp` it recognises, so the page type is
/// spelled out here instead of inferred.
Page<void> androidDefaultPage(GoRouterState state, Widget child) {
  // Keep `state.pageKey`: go_router uses it to recognise a new state of the same
  // route, otherwise every push/pop rebuilds the subtree and loses state.
  return DefaultPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    child: child,
  );
}

/// A sub page; the view width picks the mobile card slide or the desktop fade,
/// matching FlClash's `BaseNavigator` rather than the host platform.
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

/// The app shell's first page. It never animates itself; a card route pushed
/// over it paints above it.
class RootShellPage<T> extends RootPage<T> {
  const RootShellPage({required super.child, super.key, super.name});
}
