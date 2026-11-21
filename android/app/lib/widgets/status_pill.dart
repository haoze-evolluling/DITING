import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.foregroundColor,
    this.alpha,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    this.style = AppTextRole.badge,
    this.tabular = false,
    this.leading,
    this.leadingSize = 14,
  });

  final String label;

  final Color color;

  final Color? foregroundColor;

  final double? alpha;

  final EdgeInsets padding;
  final AppTextRole style;

  final bool tabular;

  final IconData? leading;
  final double leadingSize;

  @override
  Widget build(BuildContext context) {
    final fore = foregroundColor ?? color;
    final alpha = this.alpha;
    final label = Text(
      this.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style
          .of(context)
          .copyWith(
            color: fore,
            fontFeatures: tabular ? appTabularFigures : null,
          ),
    );
    final leading = this.leading;
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: alpha == null ? color : color.withValues(alpha: alpha),
        shape: AppShape.standard,
      ),
      child: leading == null
          ? label
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Icon(leading, size: leadingSize, color: fore),
                label,
              ],
            ),
    );
  }
}
