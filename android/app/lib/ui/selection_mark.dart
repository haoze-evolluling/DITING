// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_android/ui/context.dart';
import 'package:diting_android/ui/icons/icons.dart';
import 'package:diting_android/ui/shape.dart';
import 'package:material_ui/material_ui.dart';

class SelectionCheck extends StatelessWidget {
  const SelectionCheck({super.key});

  static const size = 24.0;

  @override
  Widget build(BuildContext context) {
    return Icon(
      TablerIcons.check,
      size: size,
      color: context.colorScheme.primary,
    );
  }
}

class SelectionBadge extends StatelessWidget {
  const SelectionBadge({super.key, this.size = 22})
    : glyph = TablerIcons.check,
      tonal = false;

  const SelectionBadge.preferred({
    super.key,
    this.size = 22,
    bool inUse = false,
  }) : glyph = TablerIcons.pin,
       tonal = !inUse;

  final double size;
  final IconData glyph;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: AppShape.standard,
          color: tonal
              ? colorScheme.primary.withValues(alpha: 0.14)
              : colorScheme.primary,
        ),
        child: Center(
          child: Icon(
            glyph,
            size: size - 6,
            color: tonal ? colorScheme.primary : colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
