import 'package:diting_shared/ui/page_routes.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Wraps a sub page in a [Page] whose route supplies FlClash's transition: a
/// horizontal card slide on mobile, a plain fade on desktop. Every route must use
/// `pageBuilder`: go_router only falls back to a theme transition for `builder`
/// when the app is a `MaterialApp` it recognises, so the page type is spelled out
/// here instead of inferred.
Page<void> androidDefaultPage(GoRouterState state, Widget child) {
  // Keep `state.pageKey`: go_router uses it to recognise a new state of the same
  // route, otherwise every push/pop rebuilds the subtree and loses state.
  final key = state.pageKey;
  final name = state.name ?? state.path;
  return defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS
      ? CardPage<void>(key: key, name: name, child: child)
      : FadePage<void>(key: key, name: name, child: child);
}

/// A [Page] that opens with [CardPageRoute].
class CardPage<T> extends Page<T> {
  const CardPage({required this.child, super.key, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) =>
      CardPageRoute<T>(settings: this, builder: (_) => child);
}

/// A [Page] that opens with [FadePageRoute].
class FadePage<T> extends Page<T> {
  const FadePage({required this.child, super.key, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) =>
      FadePageRoute<T>(settings: this, builder: (_) => child);
}
