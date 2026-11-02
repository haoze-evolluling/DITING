// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/inherited.dart';
import 'package:diting_shared/ui/liquid_glass.dart';
import 'package:diting_shared/ui/navigation_dock.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/surface.dart';
import 'package:material_ui/material_ui.dart';

/// Floats [bar] over the foot of [body] as a sheet's docked search floats,
/// in the dock's fill and shadow or its glass, and lets [body] scroll clear
/// of it.
class FloatingFootBar extends StatelessWidget {
  const FloatingFootBar({super.key, required this.bar, required this.body});

  final Widget bar;
  final Widget body;

  static const _margin = BottomInsetScope.dockedSearchMargin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final level = SurfaceLevel.floatingOf(colorScheme);
    final content = SurfaceScope(
      level: level,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: BottomInsetScope.dockedSearchHeight,
        ),
        child: bar,
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        BottomInsetScope(
          inset:
              BottomInsetScope.of(context) + BottomInsetScope.dockedSearchInset,
          child: body,
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              _margin,
              0,
              _margin,
              _margin + context.bottomInset,
            ),
            child: LiquidGlassScope.of(context)
                ? LiquidGlass(
                    style: LiquidGlassStyle.pill(colorScheme),
                    child: content,
                  )
                : DecoratedBox(
                    decoration: ShapeDecoration(
                      color: level.colorOf(colorScheme),
                      shape: AppShape.full,
                      shadows: dockShadows(colorScheme),
                    ),
                    child: content,
                  ),
          ),
        ),
      ],
    );
  }
}
