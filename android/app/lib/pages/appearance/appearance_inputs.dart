/// Shared inputs for the appearance pages: fields and slider rows in grouped cards.
library;

import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class FieldGroupCard extends StatelessWidget {
  const FieldGroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      shape: AppShape.all(AppCorner.xl),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: children,
      ),
    );
  }
}

/// Label above a multi-line field. [FilledInputTheme] disables floating labels, so
/// it cannot live in `InputDecoration.labelText`.
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hintText,
    this.minLines = 2,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(label, style: context.listTitleStyle),
        FilledInputTheme(
          borderRadius: AppRadius.md,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            minLines: minLines,
            maxLines: null,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(hintText: hintText),
          ),
        ),
      ],
    );
  }
}

/// A card row with a label, a percentage and a slider, hosted in
/// `DecorationListItem` host so the row shares the group card and dividers.
class SliderCardRow extends StatelessWidget {
  const SliderCardRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.1,
    this.max = 1,
    this.divisions,
    this.glyph,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int? divisions;
  final Glyph? glyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final percent = '${(value * 100).round()}%';
    return DecorationListItem(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      minVerticalPadding: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          Row(
            spacing: 10,
            children: [
              if (glyph != null)
                GlyphIcon(
                  glyph!,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
              Expanded(child: Text(label, style: context.listTitleStyle)),
              Text(
                percent,
                style: context.listSubtitleStyle.copyWith(
                  fontFeatures: appTabularFigures,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: percent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
