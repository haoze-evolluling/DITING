/// The DNS64 synthesizer: the engine switch, what it does and the protections the service applies on
/// its own.
///
/// The old desktop console's `DNS64Panel.vue` is the blueprint. The switch saves the moment it moves and
/// both writes re-read `/status`, so a prefix the service rejected never stays on screen as if it had
/// been applied. The prefix list is [Dns64PrefixesCard], because a five-line editor next to the long
/// explanation made one card taller than the window.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_dns64_models.dart';
import 'package:diting_desktop/data/api/desktop_dns64_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class Dns64Card extends ConsumerWidget {
  const Dns64Card({super.key, required this.config, required this.saving});

  final DesktopDns64Config config;
  final bool saving;

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool enabled) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopDns64Provider.notifier)
        .save(config.copyWith(enabled: enabled));
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (enabled ? l10n.desktopDns64ToggleOn : l10n.desktopDns64ToggleOff)
          : l10n.desktopDns64SaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopDns64CardTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: l10n.desktopDns64CardTitle,
            leading: [
              DashboardChip(
                label: config.enabled
                    ? l10n.desktopDns64EngineOn
                    : l10n.desktopDns64EngineOff,
                tone: config.enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: true,
              ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardSwitch(
                  value: config.enabled,
                  semanticLabel: l10n.desktopDns64CardTitle,
                  onChanged: (value) =>
                      unawaited(_toggle(context, ref, value)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.desktopDns64CardBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.desktopDns64Description,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 14),
          DashboardBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    GlyphIcon(
                      AppGlyphs.info,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    Expanded(
                      child: Text(
                        l10n.desktopDns64NoteTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardText.rowTitle(context),
                      ),
                    ),
                  ],
                ),
                Text(
                  l10n.desktopDns64NoteBody,
                  style: DashboardText.label(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
