library;

import 'dart:ui' show ImageFilter;

import 'package:diting_android/state/appearance_extra_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

part 'mini_screen_painter.dart';

enum MiniPage { dashboard, rules, logs, tools }

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

  late final double pageBottom;
  late final Rect bar;
}
