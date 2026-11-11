/// Choice group with thumbnails (upstream `PreviewChoiceGroup`).
library;

import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class PreviewChoice<T> {
  const PreviewChoice({
    required this.value,
    required this.label,
    required this.pictogram,
    this.description,
  });

  final T value;
  final String label;

  /// Thumbnail on the left; the caller constrains its size.
  final Widget pictogram;

  /// Optional one-line note when the label alone cannot tell items apart.
  final String? description;
}

class PreviewChoiceGroup<T> extends StatelessWidget {
  const PreviewChoiceGroup({
    super.key,
    required this.info,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.footer,
  });

  final Info info;
  final List<PreviewChoice<T>> choices;
  final T value;
  final ValueChanged<T> onChanged;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoHeader(info: info),
        // Horizontal padding comes from `generateSection`/`ListFooter`, which each
        // add 16; adding it here too would indent the header by 32.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              generateSection(
                items: [
                  for (final choice in choices)
                    DecorationListItem(
                      leading: ExcludeSemantics(child: choice.pictogram),
                      title: Text(choice.label),
                      subtitle: switch (choice.description) {
                        final description? => Text(description),
                        null => null,
                      },
                      isSelected: choice.value == value,
                      trailing: choice.value == value
                          ? const SelectionCheck()
                          : null,
                      onPressed: () => onChanged(choice.value),
                    ),
                ],
              ),
              if (footer case final footer?) ListFooter(text: footer),
            ],
          ),
        ),
      ],
    );
  }
}
