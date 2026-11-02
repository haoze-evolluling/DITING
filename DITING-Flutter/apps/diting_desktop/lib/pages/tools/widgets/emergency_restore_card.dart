/// The emergency network restore: put the host's DNS back the way it was before the takeover, clear
/// residual loopback DNS and flush the system cache.
///
/// The old desktop console kept this behind a Wails binding (`App.RunEmergencyRestore`), so only its
/// desktop window could offer it. The service now answers `POST /takeover/emergency-restore`, so the
/// same card works in the desktop window and in the LAN console — and it never runs without the
/// confirmation, because it rewrites the host's DNS settings.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_tools_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class EmergencyRestoreCard extends ConsumerWidget {
  const EmergencyRestoreCard({super.key});

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopToolsEmergencyConfirmTitle,
      body: l10n.desktopToolsEmergencyConfirmBody,
      confirmLabel: l10n.desktopToolsEmergencyAction,
      destructive: false,
    );
    if (!confirmed || !context.mounted) return;
    final error = await ref
        .read(desktopEmergencyRestoreProvider.notifier)
        .restore();
    if (!context.mounted) return;
    final message = ref.read(desktopEmergencyRestoreProvider).result?.message;
    showDesktopMessage(
      context,
      error == null
          ? (message == null || message.isEmpty
                ? l10n.desktopToolsEmergencyDone
                : message)
          : l10n.desktopToolsEmergencyFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopEmergencyRestoreProvider);
    final colorScheme = context.colorScheme;
    final result = state.result;
    return DashboardCard(
      semanticLabel: l10n.desktopToolsEmergencyTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.undo,
            title: l10n.desktopToolsEmergencyTitle,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopToolsEmergencyBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: state.busy
                  ? null
                  : () => unawaited(_restore(context, ref)),
              icon: state.busy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CommonCircleLoading(),
                    )
                  : const GlyphIcon(AppGlyphs.refresh, size: 16),
              label: Text(
                state.busy
                    ? l10n.desktopToolsEmergencyBusy
                    : l10n.desktopToolsEmergencyAction,
              ),
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 10),
            DashboardBlock(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                spacing: 8,
                children: [
                  GlyphIcon(
                    result.healed
                        ? AppGlyphs.checkCircle
                        : AppGlyphs.info,
                    size: 16,
                    color: result.healed
                        ? colorScheme.success
                        : colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Text(
                      result.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardText.label(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.desktopToolsEmergencyFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}
