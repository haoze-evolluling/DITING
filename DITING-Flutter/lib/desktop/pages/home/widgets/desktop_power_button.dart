/// The dashboard's primary action, in the app bar where upstream keeps its core button: it starts
/// or stops the DNS listener, and the service, not this widget, decides what state that leaves.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showFloatingDialog<bool>(
    context: context,
    child: CommonDialog(
      title: title,
      destructive: true,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context, false),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => popFloatingDialog(context, true),
          child: Text(context.l10n.commonConfirm),
        ),
      ],
      child: Text(message),
    ),
  );
  return confirmed ?? false;
}

class DesktopPowerButton extends ConsumerWidget {
  const DesktopPowerButton({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final control = ref.watch(desktopControlProvider);
    final pending = control.pending;
    final running = status.dns.running;
    final busy =
        pending == DesktopControlAction.startDns ||
        pending == DesktopControlAction.stopDns;
    final label = switch (pending) {
      DesktopControlAction.startDns => l10n.stateStarting,
      DesktopControlAction.stopDns => l10n.stateStopping,
      _ => running ? l10n.desktopStopDns : l10n.desktopStartDns,
    };
    final foreground = running
        ? colorScheme.onSuccessContainer
        : colorScheme.onErrorContainer;

    Future<void> onPressed() async {
      if (busy) return;
      final confirmed = await _confirm(
        context,
        title: running ? l10n.desktopStopDnsTitle : l10n.desktopStartDnsTitle,
        message: running
            ? l10n.desktopStopDnsMessage
            : l10n.desktopStartDnsMessage,
      );
      if (!confirmed || !context.mounted) return;
      await ref.read(desktopControlProvider.notifier).toggleDns();
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: running
              ? colorScheme.successContainer
              : colorScheme.errorContainer,
          foregroundColor: foreground,
        ),
        icon: busy
            ? CommonCircleLoading(size: 18, color: foreground)
            : GlyphIcon(
                running ? AppGlyphs.check : AppGlyphs.bolt,
                size: 18,
                color: foreground,
              ),
        label: Text(label),
      ),
    );
  }
}
