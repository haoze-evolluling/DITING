// ignore_for_file: sort_child_properties_last
import 'package:diting_android/data/cleanup/cleanup_models.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CleanupRunningBanner extends StatelessWidget {
  const CleanupRunningBanner({super.key, required this.action});

  final CleanupAction action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        spacing: 8,
        children: [
          const CommonCircleLoading(size: 16),
          Expanded(
            child: Text(
              context.l10n.cleanupRunning(action.title(context.l10n)),
              style: AppTextRole.supportingText.of(context),
            ),
          ),
        ],
      ),
    );
  }
}

class CleanupActionTile extends ConsumerWidget {
  const CleanupActionTile({
    super.key,
    required this.action,
    required this.enabled,
  });

  final CleanupAction action;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListItem(
      leading: Icon(
        TablerIcons.trash,
        size: 20,
        color: context.colorScheme.error,
      ),
      title: Text(
        action.title(context.l10n),
        style: AppTextRole.rowTitle
            .of(context)
            .copyWith(color: context.colorScheme.error),
      ),
      subtitle: Text(action.description(context.l10n)),
      onTap: enabled ? () => runCleanupAction(context, ref, action) : null,
    );
  }
}

Future<void> runCleanupAction(
  BuildContext context,
  WidgetRef ref,
  CleanupAction action,
) async {
  final confirmed = await showFloatingDialog<bool>(
    context: context,
    child: CommonDialog(
      title: action.title(context.l10n),
      destructive: true,
      child: Text(action.confirmText(context.l10n)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.commonConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final result = await ref.read(cleanupRunnerProvider).run(action);
  if (!context.mounted) return;

  showAppSnack(context, result.message);

  if (action.exitsApp) {
    await _exitApp(context);
  }
}

Future<void> _exitApp(BuildContext context) async {
  final confirmed = await showFloatingDialog<bool>(
    context: context,
    child: CommonDialog(
      title: context.l10n.cleanupRestartTitle,
      child: Text(context.l10n.cleanupRestartBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.devQuitNow),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await SystemNavigator.pop();
  }
}
