import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, this.value, this.minHeight = 6, this.color});

  final double? value;
  final double minHeight;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRSuperellipse(
      borderRadius: AppRadius.standard,
      child: LinearProgressIndicator(
        value: value,
        minHeight: minHeight,
        backgroundColor: context.raisedSurfaceLevel.colorOf(
          context.colorScheme,
        ),
        color: color,
      ),
    );
  }
}
