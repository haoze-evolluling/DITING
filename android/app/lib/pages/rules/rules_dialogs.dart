part of 'rules_page.dart';

/// Input dialog for a rewrite rule: domain plus target value. InputDialog takes one field,
/// and two chained dialogs would leave the user unsure where they were after cancelling.
class _RuleDialog extends StatefulWidget {
  const _RuleDialog({
    required this.title,
    required this.initialPattern,
    this.initialTarget,
    this.existingPatterns = const {},
  });

  final String title;
  final String initialPattern;
  final String? initialTarget;

  /// Existing patterns, used to report duplicates in place instead of after closing.
  final Set<String> existingPatterns;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _pattern = TextEditingController(text: widget.initialPattern);
  late final _target = TextEditingController(text: widget.initialTarget ?? '');

  @override
  void dispose() {
    _pattern.dispose();
    _target.dispose();
    super.dispose();
  }

  String? _validatePattern(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return context.l10n.rulePatternRequired;
    }
    if (text.contains('#@#')) {
      return context.l10n.ruleAllowNeedsAllowlist;
    }
    if (widget.existingPatterns.contains(text)) {
      return context.l10n.ruleAlreadyExists;
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop<({String pattern, String? target})>((
      pattern: _pattern.text.trim(),
      target: _target.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = UiLocalizations.of(context);
    return CommonDialog(
      title: widget.title,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(localizations.submit)),
      ],
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          spacing: 12,
          children: [
            TextFormField(
              controller: _pattern,
              autofocus: true,
              maxLines: null,
              minLines: 1,
              validator: _validatePattern,
              decoration: InputDecoration(
                hintText: context.l10n.ruleDomainHint,
              ),
            ),
            TextFormField(
              controller: _target,
              maxLines: null,
              minLines: 1,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? context.l10n.ruleTargetRequired : null,
              decoration: InputDecoration(hintText: context.l10n.ruleTargetHint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared confirmation dialog. Only true runs a destructive action. Clear, delete and the
/// whitelist relax all use it because there is no undo.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final localizations = UiLocalizations.of(context);
  final result = await showFloatingDialog<bool>(
    context: context,
    child: CommonDialog(
      title: title,
      destructive: true,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context, false),
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () => popFloatingDialog(context, true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(message),
    ),
  );
  return result ?? false;
}
