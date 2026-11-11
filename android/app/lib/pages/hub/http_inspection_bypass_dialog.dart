/// Bypass domain dialog for HTTPS inspection. The controller is owned by the dialog: disposing it
/// right after `await` fires on `pop` mid animation and trips `'_dependents.isEmpty': is not true`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class HttpInspectionBypassDialog extends StatefulWidget {
  const HttpInspectionBypassDialog({super.key});

  @override
  State<HttpInspectionBypassDialog> createState() =>
      _HttpInspectionBypassDialogState();
}

class _HttpInspectionBypassDialogState extends State<HttpInspectionBypassDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.bypassAddTitle,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.configCancel),
        ),
        TextButton(onPressed: _submit, child: Text(context.l10n.bypassAdd)),
      ],
      child: TextField(
        controller: _controller,
        autocorrect: false,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: context.l10n.bypassSuffix,
          hintText: 'example.com',
          helperText: context.l10n.bypassSuffixBody,
        ),
      ),
    );
  }
}
