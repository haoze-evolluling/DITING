import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

typedef BootstrapEntryDraft = ({String name, String ip});

class BootstrapEntryEditor extends StatefulWidget {
  const BootstrapEntryEditor({super.key});

  @override
  State<BootstrapEntryEditor> createState() => _BootstrapEntryEditorState();
}

class _BootstrapEntryEditorState extends State<BootstrapEntryEditor> {
  static final _addressPattern = RegExp(
    r'^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$|^[0-9a-fA-F:]+$',
  );

  final _name = TextEditingController();
  final _ip = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    super.dispose();
  }

  void _save() {
    final ip = _ip.text.trim();
    if (!_addressPattern.hasMatch(ip)) {
      setState(() => _error = currentL10n.bootstrapInvalidIp);
      return;
    }
    Navigator.of(context).pop((name: _name.text.trim(), ip: ip));
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.bootstrapAdd,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.appRulesCancel),
        ),
        TextButton(
          onPressed: _save,
          child: Text(context.l10n.appSelectionSave),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: context.l10n.bootstrapNameOptional,
            ),
          ),
          TextField(
            controller: _ip,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.l10n.bootstrapIpAddress,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: AppTextRole.supportingText
                  .of(context)
                  .copyWith(color: context.colorScheme.error),
            ),
        ],
      ),
    );
  }
}
