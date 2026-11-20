import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// A page-level paragraph with no card around it: indented 16 and pushed 12 below the app bar.
class PageIntroText extends StatelessWidget {
  const PageIntroText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(text, style: AppTextRole.supportingText.of(context)),
    );
  }
}
