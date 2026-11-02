part of 'user_agents_page.dart';

/// Add or edit a User-Agent; an empty [existing] means a new entry.
Future<void> showUserAgentDialog(
  BuildContext context,
  WidgetRef ref, {
  String? existing,
}) async {
  final agents = ref.read(configResourcesProvider).userAgents;
  final value = await showFloatingDialog<String>(
    context: context,
    child: InputDialog(
      title: existing == null ? context.l10n.uaAdd : context.l10n.uaEdit,
      value: existing ?? '',
      hintText: context.l10n.uaHint,
      labelText: 'User-Agent',
      maxLength: TextInputLimits.userAgent,
      selectAll: existing != null,
      validator: (input) {
        final text = (input ?? '').trim();
        if (text.isEmpty) {
          return context.l10n.uaEmptyError;
        }
        if (text != existing && agents.any((item) => item.value == text)) {
          return context.l10n.uaDuplicateError;
        }
        return null;
      },
    ),
  );
  if (value == null || !context.mounted) {
    return;
  }
  final notifier = ref.read(configResourcesProvider.notifier);
  final ok = existing == null
      ? notifier.addUserAgent(value)
      : notifier.updateUserAgent(existing, value);
  if (!ok) {
    showConfigHint(context, context.l10n.uaDuplicateError);
  }
}
