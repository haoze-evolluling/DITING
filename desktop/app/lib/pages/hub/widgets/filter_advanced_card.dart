/// The advanced blocking switches: response-side CNAME re-checking and allowlist-only mode.
///
/// The old desktop console's `RulesPanel.vue` "advanced" tab is the blueprint. Each switch saves on the
/// spot. The bogus-NXDOMAIN correction with its address list is [BogusNxDomainCard], because a list
/// editor inside the switch card made it the tallest card on the page.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_filter_config_models.dart';
import 'package:diting_desktop/data/api/desktop_filter_config_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The four addresses the console offers as one-tap entries.
const List<String> desktopBogusPresets = [
  '0.0.0.0/8',
  '127.0.0.0/8',
  '::/128',
  '::1/128',
];

/// Obvious typos only; the service is the authority on what a valid address is.
final RegExp _addressShape = RegExp(r'^[0-9a-fA-F:.]+(/\d{1,3})?$');

List<String> desktopBogusNetworks(String text) => [
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

class FilterAdvancedCard extends ConsumerWidget {
  const FilterAdvancedCard({
    super.key,
    required this.config,
    required this.saving,
  });

  final DesktopFilterConfig config;
  final bool saving;

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    DesktopFilterConfig next, {
    required String success,
  }) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopFilterConfigProvider.notifier)
        .save(next);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? success
          : l10n.desktopFilterConfigSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final saving = this.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopFilterAdvancedTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.rules,
            title: l10n.desktopFilterAdvancedTitle,
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
            l10n.desktopFilterAdvancedBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          FilterToggleRow(
            title: l10n.desktopFilterAdvancedResponseTitle,
            body: l10n.desktopFilterAdvancedResponseBody,
            value: config.filterResponse,
            onChanged: saving
                ? null
                : (value) => unawaited(
                    _toggle(
                      context,
                      ref,
                      config.copyWith(filterResponse: value),
                      success: value
                          ? l10n.desktopFilterAdvancedResponseOn
                          : l10n.desktopFilterAdvancedResponseOff,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          FilterToggleRow(
            title: l10n.desktopFilterAdvancedAllowlistTitle,
            body: l10n.desktopFilterAdvancedAllowlistBody,
            value: config.allowlistOnly,
            warning: l10n.desktopFilterAdvancedAllowlistWarning,
            onChanged: saving
                ? null
                : (value) => unawaited(
                    _toggle(
                      context,
                      ref,
                      config.copyWith(allowlistOnly: value),
                      success: value
                          ? l10n.desktopFilterAdvancedAllowlistOn
                          : l10n.desktopFilterAdvancedAllowlistOff,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The bogus-NXDOMAIN correction: the switch and the address list that marks an upstream answer as a
/// hijack page.
class BogusNxDomainCard extends ConsumerStatefulWidget {
  const BogusNxDomainCard({
    super.key,
    required this.config,
    required this.saving,
  });

  final DesktopFilterConfig config;
  final bool saving;

  @override
  ConsumerState<BogusNxDomainCard> createState() => _BogusNxDomainCardState();
}

class _BogusNxDomainCardState extends ConsumerState<BogusNxDomainCard> {
  final _networks = TextEditingController();
  DesktopFilterConfig? _adopted;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.config);
  }

  @override
  void didUpdateWidget(BogusNxDomainCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.config);
  }

  @override
  void dispose() {
    _networks.dispose();
    super.dispose();
  }

  void _adopt(DesktopFilterConfig config) {
    if (identical(_adopted, config)) return;
    _adopted = config;
    if (_dirty) return;
    _networks.text = config.bogusNxDomainNetworks.join('\n');
  }

  Future<void> _toggle(
    DesktopFilterConfig next, {
    required String success,
  }) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopFilterConfigProvider.notifier)
        .save(next);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? success
          : l10n.desktopFilterConfigSaveFailed(error.message),
    );
  }

  Future<void> _saveNetworks() async {
    final l10n = context.l10n;
    final lines = desktopBogusNetworks(_networks.text);
    final error = await ref
        .read(desktopFilterConfigProvider.notifier)
        .save(widget.config.copyWith(bogusNxDomainNetworks: lines));
    if (!mounted) return;
    if (error == null) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null
          ? (lines.isEmpty
                ? l10n.desktopFilterAdvancedBogusCleared
                : l10n.desktopFilterAdvancedBogusSaved(lines.length))
          : l10n.desktopFilterConfigSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = widget.config;
    final saving = widget.saving;
    final suspicious = desktopBogusNetworks(_networks.text)
        .where((entry) => !_addressShape.hasMatch(entry))
        .toList();
    return DashboardCard(
      semanticLabel: l10n.desktopFilterAdvancedBogusTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.warning,
            title: l10n.desktopFilterAdvancedBogusTitle,
            leading: [
              DashboardChip(
                label: config.bogusNxDomain
                    ? l10n.commonEnabled
                    : l10n.commonDisabled,
                tone: config.bogusNxDomain
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: config.bogusNxDomain,
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
                  value: config.bogusNxDomain,
                  semanticLabel: l10n.desktopFilterAdvancedBogusTitle,
                  onChanged: (value) => unawaited(
                    _toggle(
                      config.copyWith(bogusNxDomain: value),
                      success: value
                          ? l10n.desktopFilterAdvancedBogusOn
                          : l10n.desktopFilterAdvancedBogusOff,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopFilterAdvancedBogusBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (config.bogusNxDomain) ...[
            const SizedBox(height: 12),
            Text(
              l10n.desktopFilterAdvancedBogusListLabel,
              style: DashboardText.rowTitle(context),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _networks,
              minLines: 3,
              maxLines: 6,
              style: AppTextStyle.callout.of(context).toTabular,
              decoration: InputDecoration(
                hintText: desktopBogusPresets.take(2).join('\n'),
              ),
              onChanged: (_) => setState(() => _dirty = true),
            ),
            if (suspicious.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                l10n.desktopFilterAdvancedBogusSuspicious(
                  suspicious.join(', '),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.label(
                  context,
                  color: context.colorScheme.warning,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.desktopFilterAdvancedBogusPresets,
                  style: DashboardText.label(context),
                ),
                for (final preset in desktopBogusPresets)
                  OutlinedButton(
                    onPressed: saving
                        ? null
                        : () {
                            final lines = desktopBogusNetworks(
                              _networks.text,
                            );
                            if (lines.contains(preset)) return;
                            setState(() {
                              _dirty = true;
                              _networks.text = [...lines, preset].join('\n');
                            });
                          },
                    child: Text(preset, style: AppTextStyle.caption1.of(context)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              spacing: 8,
              children: [
                const Spacer(),
                if (_dirty)
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => setState(() {
                            _dirty = false;
                            _networks.text = config.bogusNxDomainNetworks
                                .join('\n');
                          }),
                    child: Text(l10n.desktopFilterAdvancedBogusReset),
                  ),
                FilledButton.tonal(
                  onPressed: saving ? null : () => unawaited(_saveNetworks()),
                  child: Text(l10n.desktopFilterAdvancedBogusSave),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
