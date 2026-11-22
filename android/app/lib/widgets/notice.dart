import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.message,
    this.glyph = TablerIcons.alert_triangle,
    this.color,
    this.foregroundColor,
    this.glyphSize = 16,
    this.padding = const EdgeInsets.all(10),
  });

  final String message;
  final IconData glyph;

  final Color? color;
  final Color? foregroundColor;
  final double glyphSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final background = color ?? colorScheme.warningContainer;
    final foreground = foregroundColor ?? colorScheme.onWarningContainer;
    return Container(
      padding: padding,
      decoration: ShapeDecoration(shape: AppShape.standard, color: background),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Icon(glyph, size: glyphSize, color: foreground),
          Expanded(
            child: Text(
              message,
              style: AppTextRole.supportingText
                  .of(context)
                  .copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class CardNoticeRow extends StatelessWidget {
  const CardNoticeRow({
    super.key,
    required this.message,
    this.glyph = TablerIcons.circle_check,
    this.color,
    this.glyphSize = 16,
  });

  final String message;
  final IconData glyph;

  final Color? color;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        spacing: 8,
        children: [
          Icon(
            glyph,
            size: glyphSize,
            color: color ?? context.colorScheme.primary,
          ),
          Expanded(
            child: Text(message, style: AppTextRole.supportingText.of(context)),
          ),
        ],
      ),
    );
  }
}
