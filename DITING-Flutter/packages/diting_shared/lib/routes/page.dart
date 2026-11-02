import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Wraps a sub page in [MaterialPage] so the theme supplies the transition. Every route must use
/// `pageBuilder`: go_router only falls back to a theme transition for `builder` when the app is a
/// `MaterialApp` it recognises, so the page type is spelled out here instead of inferred.
Page<void> androidDefaultPage(GoRouterState state, Widget child) {
  return MaterialPage<void>(
    // Keep `state.pageKey`: go_router uses it to recognise a new state of the
    // same route, otherwise every push/pop rebuilds the subtree and loses state.
    key: state.pageKey,
    name: state.name ?? state.path,
    child: child,
  );
}
