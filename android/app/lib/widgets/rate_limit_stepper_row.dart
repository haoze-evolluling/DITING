/// Shared numeric row for the LAN and connection rate-limit pages.
library;

import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class RateLimitStepperRow extends StatelessWidget {
  const RateLimitStepperRow({
    super.key,
    required this.glyph,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.enabled = true,
  });

  final Glyph glyph;
  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final canDecrease = enabled && value > min;
    final canIncrease = enabled && value < max;
    return ListItem(
      leading: GlyphIcon(glyph, size: 20),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: '$label −',
            child: IconButton(
              icon: const GlyphIcon(AppGlyphs.remove),
              onPressed: canDecrease
                  ? () => onChanged((value - step).clamp(min, max))
                  : null,
            ),
          ),
          Text(
            '$value',
            style: context.listTitleStyle.copyWith(
              fontFeatures: appTabularFigures,
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          Semantics(
            button: true,
            label: '$label +',
            child: IconButton(
              icon: const GlyphIcon(AppGlyphs.add),
              onPressed: canIncrease
                  ? () => onChanged((value + step).clamp(min, max))
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
