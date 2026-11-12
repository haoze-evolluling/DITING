// Portions derived from FlClash (https://github.com/chen08209/FlClash), Copyright (c) the FlClash authors, GPL-3.0-or-later.
import 'dart:io';

import 'package:material_ui/material_ui.dart';

/// The app's custom wallpaper, published above the navigator so a route can
/// paint it as part of its own card. The root background layer still paints the
/// image for dialogs and overlays; a moving card paints this copy so the
/// wallpaper travels with the page instead of staying static underneath it.
class PageBackgroundScope extends InheritedWidget {
  const PageBackgroundScope({super.key, this.path, required super.child});

  final String? path;

  bool get isActive => path != null && path!.isNotEmpty;

  static PageBackgroundScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageBackgroundScope>();

  static String? pathOf(BuildContext context) {
    final path = maybeOf(context)?.path;
    return path == null || path.isEmpty ? null : path;
  }

  @override
  bool updateShouldNotify(PageBackgroundScope oldWidget) =>
      path != oldWidget.path;
}

/// A page card's own copy of the wallpaper, clipped and moved with the card by
/// the route transition.
class PageCardSurface extends StatelessWidget {
  const PageCardSurface({super.key, required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: dark ? 0.34 : 0.16)),
        child,
      ],
    );
  }
}
