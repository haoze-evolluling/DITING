import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

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
