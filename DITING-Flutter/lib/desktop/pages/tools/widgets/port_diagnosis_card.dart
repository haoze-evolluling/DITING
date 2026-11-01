/// The 53-port diagnosis: run the probe, read its report, and let it stop the system listener it
/// knows how to stop.
///
/// The old desktop console's `DiagnosticsPanel.vue` port block is the blueprint. The probe is
/// on demand only, and its diagnostic text is shown as the probe wrote it.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_tools_models.dart';
import 'package:diting/desktop/data/api/desktop_tools_providers.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PortDiagnosisCard extends ConsumerWidget {
  const PortDiagnosisCard({super.key, required this.state});

  final DesktopPortCheckState state;

  Future<void> _autofix(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopToolsFixTitle,
      body: l10n.desktopToolsFixBody,
      confirmLabel: l10n.desktopToolsFix,
      destructive: false,
    );
    if (!confirmed || !context.mounted) return;
    final error = await ref.read(desktopPortCheckProvider.notifier).autofix();
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopToolsFixed
          : l10n.desktopToolsFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final result = state.result;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopToolsPortTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.wrench,
            title: l10n.desktopToolsPortTitle,
            leading: [
              if (result != null)
                DashboardChip(
                  label: result.available
                      ? l10n.desktopToolsPortOk
                      : l10n.desktopToolsPortConflict,
                  tone: result.available
                      ? DashboardChipTone.ok
                      : DashboardChipTone.warn,
                  dot: true,
                ),
            ],
            trailing: [
              if (state.busy)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                SizedBox(
                  height: 28,
                  child: DashboardIconButton(
                    glyph: AppGlyphs.search,
                    tooltip: l10n.desktopToolsCheck,
                    size: 28,
                    glyphSize: 15,
                    onPressed: () => unawaited(
                      ref.read(desktopPortCheckProvider.notifier).check(),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopToolsPortBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          if (result == null)
            Text(
              l10n.desktopToolsPortIdle,
              style: DashboardText.label(context),
            )
          else ...[
            Text(
              result.available
                  ? l10n.desktopToolsPortOk
                  : l10n.desktopToolsPortConflict,
              style: DashboardText.rowTitle(context).copyWith(
                color: result.available
                    ? colorScheme.success
                    : colorScheme.warning,
              ),
            ),
            if (result.diagnostic.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(result.diagnostic, style: DashboardText.label(context)),
            ],
            for (final conflict in result.conflicts)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ConflictRow(conflict: conflict),
              ),
            if (result.canRepair) ...[
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: state.busy
                    ? null
                    : () => unawaited(_autofix(context, ref)),
                child: Text(l10n.desktopToolsFix),
              ),
            ],
          ],
          if (state.error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopToolsFailed(error.message),
              style: DashboardText.label(context, color: colorScheme.error),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            l10n.desktopToolsPortFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({required this.conflict});

  final DesktopPortConflict conflict;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${conflict.protocol} :${conflict.port}',
                style: DashboardText.rowTitle(context).toMonospace,
              ),
              if (conflict.isICS)
                DashboardChip(
                  label: l10n.desktopToolsSystemListener,
                  tone: DashboardChipTone.warn,
                ),
              if (conflict.isSelf)
                DashboardChip(
                  label: l10n.desktopToolsSelfListener,
                  tone: DashboardChipTone.ok,
                ),
            ],
          ),
          Text(
            l10n.desktopToolsConflictOwner(
              conflict.processName.isEmpty ? '—' : conflict.processName,
              conflict.pid,
              conflict.localAddress.isEmpty ? '—' : conflict.localAddress,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context).toMonospace,
          ),
          if (conflict.serviceName.isNotEmpty)
            Text(
              l10n.desktopToolsConflictService(conflict.serviceName),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
          if (conflict.diagnosis.isNotEmpty)
            Text(conflict.diagnosis, style: DashboardText.label(context)),
        ],
      ),
    );
  }
}
