part of 'user_agents_page.dart';

/// Add or edit a User-Agent. Both the display name and the UA string are edited
/// together; an empty [existing] means a new entry.
Future<void> showUserAgentDialog(
  BuildContext context,
  WidgetRef ref, {
  MockUserAgent? existing,
}) async {
  final agents = ref.read(configResourcesProvider).userAgents;
  final result = await showFloatingDialog<({String name, String value})>(
    context: context,
    child: _UserAgentDialog(agents: agents, initial: existing),
  );
  if (result == null || !context.mounted) {
    return;
  }
  final notifier = ref.read(configResourcesProvider.notifier);
  final ok = existing == null
      ? notifier.addUserAgent(result.value, name: result.name)
      : notifier.updateUserAgent(
          existing.value,
          result.value,
          name: result.name,
        );
  if (!ok) {
    showConfigHint(context, context.l10n.uaDuplicateError);
  }
}

/// Name + UA string editor. The controllers live in the dialog: disposing them
/// from `whenComplete` fires on `pop` while the fields still animate out.
class _UserAgentDialog extends StatefulWidget {
  const _UserAgentDialog({required this.agents, this.initial});

  /// Existing rows, used to reject a name or value already taken.
  final List<MockUserAgent> agents;
  final MockUserAgent? initial;

  @override
  State<_UserAgentDialog> createState() => _UserAgentDialogState();
}

class _UserAgentDialogState extends State<_UserAgentDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _value = TextEditingController(text: widget.initial?.value ?? '');

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  String get _nameText => _name.text.trim();

  String get _valueText => _value.text.trim();

  /// A name or value is taken when another row already holds it.
  bool get _nameTaken =>
      _nameText.isNotEmpty &&
      widget.agents.any(
        (a) => a.value != widget.initial?.value && a.name == _nameText,
      );

  bool get _valueTaken =>
      _valueText.isNotEmpty &&
      widget.agents.any(
        (a) => a.value != widget.initial?.value && a.value == _valueText,
      );

  bool get _valid =>
      _nameText.isNotEmpty &&
      _valueText.isNotEmpty &&
      !_nameTaken &&
      !_valueTaken;

  /// Shown once the user started filling one field but left the other empty.
  bool get _partiallyEmpty =>
      (_nameText.isNotEmpty && _valueText.isEmpty) ||
      (_valueText.isNotEmpty && _nameText.isEmpty);

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop((name: _nameText, value: _valueText));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final errorStyle = AppTextRole.supportingText
        .of(context)
        .copyWith(color: colorScheme.error);
    return CommonDialog(
      title: widget.initial == null ? context.l10n.uaAdd : context.l10n.uaEdit,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(
          onPressed: _valid ? _submit : null,
          child: Text(context.l10n.commonSave),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.initial == null,
            inputFormatters: TextInputLimits.limit(TextInputLimits.name),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.l10n.uaNameLabel,
              hintText: context.l10n.uaNameHint,
            ),
          ),
          TextField(
            controller: _value,
            autocorrect: false,
            inputFormatters: TextInputLimits.limit(TextInputLimits.userAgent),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'User-Agent',
              hintText: context.l10n.uaHint,
            ),
          ),
          if (_nameTaken || _valueTaken)
            Text(context.l10n.uaDuplicateError, style: errorStyle)
          else if (_partiallyEmpty)
            Text(context.l10n.uaEmptyError, style: errorStyle),
        ],
      ),
    );
  }
}
