// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:async';
import 'dart:math';

import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/scroll_behavior.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/surface.dart';
import 'package:diting_shared/ui/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'inherited.dart';
part 'scroll_a.dart';
part 'scroll_b.dart';

const _restThickness = 6.0;
const _activeThickness = 10.0;
const _crossAxisMargin = 2.0;
const _minThumbLength = 48.0;
const _bottomInsetGap = 8.0;

// Each band the pointer strays sideways from the thumb halves the content's travel.
const _scrubBandWidth = 48.0;
const _scrubRates = [1.0, 0.5, 0.25, 0.125];

class CommonScrollBar extends StatelessWidget {
  final ScrollController? controller;
  final Widget child;
  final bool thumbVisibility;
  final EdgeInsets padding;

  final ValueChanged<double?>? onScrub;

  final bool _hidesAmbientBar;

  const CommonScrollBar({
    super.key,
    required this.child,
    required this.controller,
    this.thumbVisibility = false,
    this.padding = EdgeInsets.zero,
    this.onScrub,
  }) : _hidesAmbientBar = true;

  const CommonScrollBar.ambient({
    super.key,
    required this.child,
    required this.controller,
    this.padding = EdgeInsets.zero,
  }) : thumbVisibility = false,
       onScrub = null,
       _hidesAmbientBar = false;

  Widget _buildScrollBar(BuildContext context, Widget child) {
    return _AppScrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      onScrub: onScrub,
      child: _hidesAmbientBar
          ? ScrollConfiguration(
              behavior: _OwnBarScrollBehavior(
                ambient: ScrollConfiguration.of(context),
                controller:
                    controller ?? PrimaryScrollController.maybeOf(context),
              ),
              child: child,
            )
          : child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = this.padding + EdgeInsets.only(top: _barClearance(context));
    if (padding == EdgeInsets.zero) {
      return _buildScrollBar(context, child);
    }
    // Scrollbar insets its track by MediaQuery padding; give it its own and not the child.
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(padding: mediaQuery.padding + padding),
      child: _buildScrollBar(
        context,
        MediaQuery(data: mediaQuery, child: child),
      ),
    );
  }
}

/// What of the floating bar MediaQuery padding leaves to cover.
double _barClearance(BuildContext context) {
  final overlap = FloatingBarScope.of(context) ?? 0;
  return max(0.0, overlap - MediaQuery.paddingOf(context).top);
}

/// The ambient behavior less the bar it would stack on the scrollable [controller] drives.
class _OwnBarScrollBehavior extends ScrollBehavior {
  const _OwnBarScrollBehavior({
    required this.ambient,
    required this.controller,
  });

  final ScrollBehavior ambient;
  final ScrollController? controller;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (details.controller == controller) {
      return child;
    }
    return ambient.buildScrollbar(context, child, details);
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => ambient.buildOverscrollIndicator(context, child, details);

  @override
  Set<PointerDeviceKind> get dragDevices => ambient.dragDevices;

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      ambient.pointerAxisModifiers;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      ambient.getMultitouchDragStrategy(context);

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      ambient.getPlatform(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      ambient.getScrollPhysics(context);

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => ambient.getKeyboardDismissBehavior(context);

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      ambient.velocityTrackerBuilder(context);

  @override
  bool shouldNotify(_OwnBarScrollBehavior oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.ambient.runtimeType != ambient.runtimeType ||
      ambient.shouldNotify(oldDelegate.ambient);
}

class _AppScrollbar extends RawScrollbar {
  final ValueChanged<double?>? onScrub;

  const _AppScrollbar({
    required super.child,
    super.controller,
    super.thumbVisibility,
    this.onScrub,
  }) : super(
         interactive: true,
         shape: AppShape.full,
         minThumbLength: _minThumbLength,
         crossAxisMargin: _crossAxisMargin,
         fadeDuration: const Duration(milliseconds: 250),
         // Long enough to let go and grab the thumb again before it fades.
         timeToFade: const Duration(milliseconds: 1200),
       );

  @override
  RawScrollbarState<_AppScrollbar> createState() => _AppScrollbarState();
}
