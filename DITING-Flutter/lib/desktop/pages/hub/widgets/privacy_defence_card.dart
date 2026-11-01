/// The two built-in defence modules: DNS rebinding protection with its allowlist, and the local
/// hosts resolver.
///
/// The old desktop console's `PrivacyPanel.vue` (rebinding + hosts blocks and its modal) is the
/// blueprint. Every switch saves on the spot; the allowlist is edited in a dialog and posted with
/// its own button.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_privacy_models.dart';
import 'package:diting/desktop/data/api/desktop_privacy_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
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

  Future<void> _write(
    BuildContext context,
    WidgetRef ref,
    Future<Object?> Function() action,
    String success,
  ) async {
    final l10n = context.l10n;
    final error = await action();
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null ? success : l10n.desktopPrivacySaveFailed('$error'),
    );
  }

  Future<void> _editDomains(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final domains = await showRebindDomainsDialog(
      context,
      allowed: config.rebindAllowedDomains,
    );
    if (domains == null || !context.mounted) return;
    await _write(
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
      semanticLabel: l10n.desktopPrivacyDefenceTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.lock,
            title: l10n.desktopPrivacyDefenceTitle,
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopPrivacyDefenceBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          FilterToggleRow(
            title: l10n.desktopPrivacyRebindTitle,
            body: l10n.desktopPrivacyRebindBody,
            value: config.rebindEnabled,
            onChanged: saving
                ? null
                : (value) => unawaited(
                    _write(
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
          const SizedBox(height: 6),
          Row(
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
          const SizedBox(height: 8),
          FilterToggleRow(
            title: l10n.desktopPrivacyHostsTitle,
            body: l10n.desktopPrivacyHostsBody,
            value: config.hostsEnabled,
            onChanged: saving
                ? null
                : (value) => unawaited(
                    _write(
                      context,
                      ref,
                      () =>
                          notifier.setHosts(config.copyWith(hostsEnabled: value)),
                      value
                          ? l10n.desktopPrivacyHostsOn
                          : l10n.desktopPrivacyHostsOff,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
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
                          _write(
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
  late final _text = TextEditingController(text: widget.allowed.join('\n'));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<String> get _domains => [
    for (final line in _text.text.split('\n'))
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
          onPressed: () => popFloatingDialog(context, _domains),
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
              controller: _text,
              minLines: 6,
              maxLines: 10,
              style: AppTextStyle.callout.of(context).toMonospace,
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
