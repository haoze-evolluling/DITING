/// Port change and stats reset shared by the three server tabs, so failure copy cannot drift.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const serverPortMin = 1024;
const serverPortMax = 65535;

Future<int?> promptServerPort(BuildContext context, int current) async {
  final result = await showFloatingDialog<String>(
    context: Navigator.of(context, rootNavigator: true).context,
    child: InputDialog(
      title: context.l10n.serverListenPort,
      value: '$current',
      suffixText: '',
      hintText: '$serverPortMin–$serverPortMax',
      keyboardType: TextInputType.number,
      maxLength: 5,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (value) {
        final parsed = int.tryParse(value?.trim() ?? '');
        if (parsed == null) {
          return context.l10n.serverPortInvalid;
        }
        if (parsed < serverPortMin || parsed > serverPortMax) {
          return currentL10n.serverPortRange(
            '$serverPortMin',
            '$serverPortMax',
          );
        }
        return null;
      },
    ),
  );
  return int.tryParse(result?.trim() ?? '');
}

Future<void> editServerPort(BuildContext context, WidgetRef ref) async {
  final port = ref.read(serverPortProvider);
  final value = await promptServerPort(context, port);
  if (value == null) {
    return;
  }
  ref.read(serverPortProvider.notifier).set(value);
  if (context.mounted) {
    showServerHint(context, context.l10n.serverPortChanged('$value'));
  }
}

Future<void> confirmResetServerStats(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmed = await showFloatingDialog<bool>(
    context: context,
    child: CommonDialog(
      title: context.l10n.serverResetStats,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.configCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.serverResetConfirm),
        ),
      ],
      child: Text(context.l10n.serverResetStatsConfirmBody),
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  ref.read(serviceStatsProvider.notifier).reset();
  showServerHint(context, context.l10n.serverStatsReset);
}

void showServerHint(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1800),
    ),
  );
}
