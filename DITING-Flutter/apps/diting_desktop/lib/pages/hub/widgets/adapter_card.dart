/// One adapter card: its connection state, the takeover switch, the gateway and the DNS before and
/// after the takeover.
///
/// The old desktop console's `AdaptersPanel.vue` is the blueprint. The service decides whether the
/// adapter is taken over (`/status`'s `takeover.adapters`, matched by id or name) and what DNS it had
/// before; the card only reports both.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_adapters_models.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class AdapterCard extends StatelessWidget {
  const AdapterCard({
    super.key,
    required this.adapter,
    required this.takenOver,
    required this.saving,
    required this.onToggle,
  });

  final DesktopAdapter adapter;
  final bool takenOver;

  /// A write is in flight; every switch is disabled so two adapters cannot race.
  final bool saving;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = adapter.name.isEmpty ? adapter.id : adapter.name;
    final originalDns = adapter.dns.join(', ');
    return DashboardCard(
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.connections,
            title: title,
            leading: [
              DashboardChip(
                label: adapter.isUp
                    ? l10n.desktopAdaptersConnected
                    : l10n.desktopAdaptersDisconnected,
                tone: adapter.isUp
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: adapter.isUp,
              ),
              if (takenOver)
                DashboardChip(
                  label: l10n.desktopAdaptersProtecting,
                  tone: DashboardChipTone.ok,
                  dot: true,
                ),
            ],
            trailing: [
              DashboardSwitch(
                value: takenOver,
                semanticLabel: title,
                onChanged: saving ? null : onToggle,
              ),
            ],
          ),
          if (adapter.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              adapter.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Field(
                label: l10n.desktopAdaptersGateway,
                value: adapter.gateway.isEmpty
                    ? l10n.desktopAdaptersNoGateway
                    : adapter.gateway,
              ),
              _Field(
                label: l10n.desktopAdaptersIpMode,
                value: adapter.ipv4Dhcp
                    ? l10n.desktopAdaptersDhcp
                    : l10n.desktopAdaptersStatic,
              ),
            ],
          ),
          const SizedBox(height: 10),
          DashboardBlock(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 3,
              children: [
                Text(
                  l10n.desktopAdaptersOriginalDns,
                  style: DashboardText.label(context),
                ),
                Text(
                  originalDns.isEmpty
                      ? l10n.desktopAdaptersAutoDns
                      : originalDns,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context).toMonospace,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          DashboardBlock(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 3,
              children: [
                Text(
                  l10n.desktopAdaptersEffectiveDns,
                  style: DashboardText.label(context),
                ),
                Text(
                  takenOver
                      ? l10n.desktopAdaptersEffectiveLoopback
                      : l10n.desktopAdaptersEffectiveSystem,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(
                    context,
                    color: takenOver
                        ? context.colorScheme.success
                        : context.colorScheme.onSurfaceVariant,
                  ).toMonospace,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Text(label, style: DashboardText.label(context)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.rowTitle(context).toMonospace,
        ),
      ],
    );
  }
}
