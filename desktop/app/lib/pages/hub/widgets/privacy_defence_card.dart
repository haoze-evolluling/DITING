/// DNS rebinding protection: the switch and the allowlist of domains allowed to answer with a
/// private address.
///
/// The old desktop console's `PrivacyPanel.vue` (rebinding block and its modal) is the blueprint.
/// The switch saves on the spot; the allowlist is edited in a dialog and posted with its own button.
///
/// The local hosts resolver used to share this card; it is [PrivacyHostsCard] now, because two
/// independent modules and a modal button made one card taller than the window.
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

class PrivacyDefenceCard extends ConsumerWidget {
  const PrivacyDefenceCard({
    super.key,
    required this.config,
    required this.saving,
  });

  final DesktopPrivacyConfig config;
  final bool saving;

  Future<void> _editDomains(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final domains = await showRebindDomainsDialog(
      context,
      allowed: config.rebindAllowedDomains,
    );
    if (domains == null || !context.mounted) return;
    await savePrivacySetting(
      context,
      ref,
      () => ref
          .read(desktopPrivacyProvider.notifier)
          .setRebind(config.copyWith(rebindAllowedDomains: domains)),
      l10n.desktopPrivacyRebindSaved,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifier = ref.read(desktopPrivacyProvider.notifier);
    return DashboardCard(
      semanticLabel: l10n.desktopPrivacyRebindTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.lock,
            title: l10n.desktopPrivacyRebindTitle,
            leading: [
              DashboardChip(
                label: config.rebindEnabled
                    ? l10n.commonEnabled
                    : l10n.commonDisabled,
                tone: config.rebindEnabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: config.rebindEnabled,
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
                  value: config.rebindEnabled,
                  semanticLabel: l10n.desktopPrivacyRebindTitle,
                  onChanged: (value) => unawaited(
                    savePrivacySetting(
                      context,
                      ref,
                      () => notifier.setRebind(
                        config.copyWith(rebindEnabled: value),
                      ),
                      value
                          ? l10n.desktopPrivacyRebindOn
                          : l10n.desktopPrivacyRebindOff,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopPrivacyRebindBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          DashboardBlock(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    l10n.desktopPrivacyRebindCount(
                      config.rebindAllowedDomains.length,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.label(context),
                  ),
                ),
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () => unawaited(_editDomains(context, ref)),
                  icon: const GlyphIcon(AppGlyphs.settings, size: 14),
                  label: Text(l10n.desktopPrivacyRebindAllowlist),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the allowlist editor. Returns the parsed domains, or null when cancelled.
Future<List<String>?> showRebindDomainsDialog(
  BuildContext context, {
  required List<String> allowed,
}) => showFloatingDialog<List<String>>(
  context: context,
  child: _RebindDomainsDialog(allowed: allowed),
);

class _RebindDomainsDialog extends StatefulWidget {
  const _RebindDomainsDialog({required this.allowed});

  final List<String> allowed;

  @override
  State<_RebindDomainsDialog> createState() => _RebindDomainsDialogState();
}

class _RebindDomainsDialogState extends State<_RebindDomainsDialog> {
  late final _draft = TextEditingController(text: widget.allowed.join('\n'));

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  List<String> get _parsed => [
    for (final line in _draft.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: l10n.desktopPrivacyRebindDialogTitle,
      hasFields: true,
      width: 560,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => popFloatingDialog(context, _parsed),
          child: Text(l10n.desktopPrivacyRebindDialogSave),
        ),
      ],
      child: SizedBox(
        width: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              l10n.desktopPrivacyRebindDialogBody,
              style: DashboardText.label(context),
            ),
            TextField(
              controller: _draft,
              minLines: 6,
              maxLines: 10,
              style: AppTextStyle.callout.of(context).toTabular,
              decoration: InputDecoration(
                hintText: 'localhost\n.local\n.lan\n.home.arpa',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
