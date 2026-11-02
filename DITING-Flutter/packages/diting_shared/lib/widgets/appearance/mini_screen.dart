/// Mini home preview (upstream `views/theme_preview.dart`), painted in a part file.
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

part 'mini_screen_painter.dart';

// `dart:math`, `dart:ui` and `AppShape` are only used in the part file, but parts
// share the parent's import scope, so the imports must stay here.
enum MiniPage { dashboard, rules, logs, tools }

/// One miniature screen. When [previous] is set the frame freezes mid-transition at
/// [progress], which is what the tab-animation thumbnails show.
class MiniScreen extends StatelessWidget {
  const MiniScreen({
    super.key,
    required this.colorScheme,
    required this.floatingBar,
    this.liquidGlass = false,
    this.selected = 0,
    this.previous,
    this.progress = 1,
    this.transition = TabTransition.slide,
    this.onSelect,
  });

  static const int destinationCount = 4;

  final ColorScheme colorScheme;
  final bool floatingBar;

  /// Whether the floating bar is glassy; the regular bar stays solid.
  final bool liquidGlass;

  final int selected;
  final int? previous;
  final double progress;
  final TabTransition transition;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final sketch = SizedBox.expand(
      child: CustomPaint(
        painter: _MiniScreenPainter(
          colorScheme: colorScheme,
          floatingBar: floatingBar,
          liquidGlass: liquidGlass,
          selected: selected,
          previous: previous,
          progress: progress,
          transition: transition,
        ),
      ),
    );
    final onSelect = this.onSelect;
    if (onSelect == null) {
      return sketch;
    }
    return LayoutBuilder(
      builder: (_, constraints) {
        final geometry = _MiniGeometry(
          constraints.biggest,
          floatingBar: floatingBar,
        );
        return Stack(
          children: [
            sketch,
            Positioned.fromRect(
              rect: geometry.bar,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < destinationCount; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Clips the thumbnail into a phone shape (9:17). Content is painted at a fixed
/// 90x170 logical size and scaled, so the width-based geometry stays proportional.
class MiniScreenThumb extends StatelessWidget {
  const MiniScreenThumb({super.key, required this.screen});

  static const Size _logicalSize = Size(90, 170);
  static const double _shownHeight = 30;

  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _shownHeight,
      width: _shownHeight * _logicalSize.width / _logicalSize.height,
      child: ClipRSuperellipse(
        borderRadius: AppRadius.xs,
        child: FittedBox(
          child: SizedBox(
            width: _logicalSize.width,
            height: _logicalSize.height,
            child: screen,
          ),
        ),
      ),
    );
  }
}

class MiniSplitScreen extends StatelessWidget {
  const MiniSplitScreen({super.key, required this.light, required this.dark});

  final Widget light;
  final Widget dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        light,
        ClipPath(clipper: _DiagonalClipper(), child: dark),
      ],
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * 0.7, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width * 0.3, size.height)
    ..close();

  @override
  bool shouldReclip(_DiagonalClipper oldClipper) => false;
}

class _MiniGeometry {
  _MiniGeometry(this.size, {required bool floatingBar})
    : unit = size.width / 20 {
    margin = unit * 1.5;
    final barHeight = floatingBar ? unit * 3.2 : unit * 3.6;
    pageBottom = floatingBar ? 0 : barHeight;
    bar = floatingBar
        ? Rect.fromLTWH(
            margin,
            size.height - margin - barHeight,
            size.width - margin * 2,
            barHeight,
          )
        : Rect.fromLTWH(0, size.height - barHeight, size.width, barHeight);
  }

  final Size size;
  final double unit;
  late final double margin;

  /// Height taken by the dock; the floating bar takes none.
  late final double pageBottom;
  late final Rect bar;
}
