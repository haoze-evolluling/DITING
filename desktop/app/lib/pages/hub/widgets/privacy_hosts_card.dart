/// The local hosts resolver: its switch, the TTL the service answers with and whether the host's own
/// hosts file is read as well.
///
/// The old desktop console's `PrivacyPanel.vue` (hosts block) is the blueprint. The switch saves on
/// the spot; the system-file switch is disabled while the resolver itself is off, because a
/// sub-switch of a stopped module would be a lie.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:diting_desktop/data/api/desktop_privacy_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/privacy_common.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacyHostsCard extends ConsumerWidget {
  const PrivacyHostsCard({
    super.key,
    required this.config,
    required this.saving,
  });

  final DesktopPrivacyConfig config;
  final bool saving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifier = ref.read(desktopPrivacyProvider.notifier);
    return DashboardCard(
      semanticLabel: l10n.desktopPrivacyHostsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.layers,
            title: l10n.desktopPrivacyHostsTitle,
            leading: [
              DashboardChip(
                label: config.hostsEnabled
                    ? l10n.commonEnabled
                    : l10n.commonDisabled,
                tone: config.hostsEnabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: config.hostsEnabled,
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
                  value: config.hostsEnabled,
                  semanticLabel: l10n.desktopPrivacyHostsTitle,
                  onChanged: (value) => unawaited(
                    savePrivacySetting(
                      context,
                      ref,
                      () => notifier.setHosts(
                        config.copyWith(hostsEnabled: value),
                      ),
                      value
                          ? l10n.desktopPrivacyHostsOn
                          : l10n.desktopPrivacyHostsOff,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopPrivacyHostsBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          DashboardBlock(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Text(
                    l10n.desktopPrivacyHostsSystem,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.label(context),
                  ),
                ),
                Text(
                  l10n.desktopPrivacyHostsTtl(config.hostsTtl),
                  style: DashboardText.label(context),
                ),
                DashboardSwitch(
                  value: config.hostsUseSystem,
                  semanticLabel: l10n.desktopPrivacyHostsSystem,
                  onChanged: saving || !config.hostsEnabled
                      ? null
                      : (value) => unawaited(
                          savePrivacySetting(
                            context,
                            ref,
                            () => notifier.setHosts(
                              config.copyWith(hostsUseSystem: value),
                            ),
                            value
                                ? l10n.desktopPrivacyHostsSystemOn
                                : l10n.desktopPrivacyHostsSystemOff,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
