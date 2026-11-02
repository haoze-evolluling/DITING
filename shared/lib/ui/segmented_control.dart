// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/surface.dart';
import 'package:diting_shared/ui/typography.dart';
import 'package:material_ui/material_ui.dart';

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  static const double _height = 44;

  /// Line height of one `subheadline` line; the wrapped bar reserves two of them.
  static const double _lineHeight = 20;
  static const double _inset = 4;

  /// Two text lines, the inset on both sides and a little slack. The lines are scaled by the
  /// text scaler, so a large font grows the bar instead of overflowing it.
  static double _wrappedHeight(BuildContext context) =>
      2 * MediaQuery.textScalerOf(context).scale(_lineHeight) + 2 * _inset + 4;

  /// Room between a label and the segment edge; also the margin used when deciding whether the
  /// labels still fit on one line.
  static const double _labelPadding = 8;

  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// Whether [label] is wider than a segment. Measured with the emphasized style because the
  /// selected segment is the widest variant.
  static bool _overflows(
    BuildContext context,
    String label,
    double segmentWidth,
  ) {
    if (!segmentWidth.isFinite) {
      return false;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: AppTextStyle.subheadline.of(context, emphasized: true),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width > segmentWidth - 2 * _labelPadding;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final count = segments.length;
    final index = segments.indexWhere((segment) => segment.$1 == value);
    // Long labels (English mode, large text scales) get a second line instead of an ellipsis, so
    // every option stays readable; short ones keep the compact single-line bar.
    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth = (constraints.maxWidth - 2 * _inset) / count;
        final wrapped = segments.any(
          (segment) => _overflows(context, segment.$2, segmentWidth),
        );
        return Container(
          height: wrapped ? _wrappedHeight(context) : _height,
          padding: const EdgeInsets.all(_inset),
          decoration: ShapeDecoration(
            color: context.raisedSurfaceLevel.colorOf(colorScheme),
            shape: AppShape.full,
          ),
          child: Stack(
            children: [
              if (index >= 0)
                AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment: AlignmentDirectional(
                    count == 1 ? 0 : index * 2 / (count - 1) - 1,
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: colorScheme.primary,
                        shape: AppShape.full,
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final (option, label) in segments)
                    Expanded(
                      child: Semantics(
                        selected: option == value,
                        button: true,
                        child: FocusRing(
                          shape: AppShape.full,
                          standsOff: option == value,
                          child: Material(
                            type: MaterialType.transparency,
                            shape: AppShape.full,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              customBorder: AppShape.full,
                              mouseCursor: option == value
                                  ? SystemMouseCursors.basic
                                  : null,
                              splashFactory: option == value
                                  ? NoSplash.splashFactory
                                  : null,
                              // A null onTap would unfocus the selected segment.
                              onTap: option == value
                                  ? () {}
                                  : () => onChanged(option),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: _labelPadding,
                                  ),
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    textAlign: TextAlign.center,
                                    style: AppTextStyle.subheadline
                                        .of(
                                          context,
                                          emphasized: option == value,
                                        )
                                        .copyWith(
                                          color: option == value
                                              ? colorScheme.onPrimary
                                              : colorScheme
                                                    .onSurfaceVariant,
                                        ),
                                    child: Text(
                                      label,
                                      maxLines: wrapped ? 2 : 1,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
