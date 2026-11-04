/// The EDNS Client Subnet card: the switch, the strip switch, the fake subnet and the save button.
///
/// The old desktop console's `PrivacyPanel.vue` (ECS card) is the blueprint. The two switches save on
/// the spot; the subnet is a draft that saves with its button.
library;

import 'dart:async';

import 'package:diting_desktop/widgets/desktop_spacing.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:diting_desktop/data/api/desktop_privacy_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacyEcsCard extends ConsumerStatefulWidget {
  const PrivacyEcsCard({
    super.key,
    required this.config,
    required this.saving,
  });

  final DesktopPrivacyConfig config;
  final bool saving;

  @override
  ConsumerState<PrivacyEcsCard> createState() => _PrivacyEcsCardState();
}

class _PrivacyEcsCardState extends ConsumerState<PrivacyEcsCard> {
  final _subnet = TextEditingController();
  DesktopPrivacyConfig? _adopted;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.config);
  }

  @override
  void didUpdateWidget(PrivacyEcsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.config);
  }

  @override
  void dispose() {
    _subnet.dispose();
    super.dispose();
  }

  void _adopt(DesktopPrivacyConfig config) {
    if (identical(_adopted, config)) return;
    _adopted = config;
    if (_dirty) return;
    _subnet.text = config.ecsCustomSubnet;
  }

  Future<void> _save(
    DesktopPrivacyConfig next, {
    required String success,
  }) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopPrivacyProvider.notifier)
        .setEcs(next);
    if (!mounted) return;
    if (error == null) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null ? success : l10n.desktopPrivacySaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = widget.config;
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopPrivacyEcsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.locate,
            title: l10n.desktopPrivacyEcsTitle,
            trailing: [
              DashboardSwitch(
                value: config.ecsEnabled,
                semanticLabel: l10n.desktopPrivacyEcsTitle,
                onChanged: saving
                    ? null
                    : (value) => unawaited(
                        _save(
                          config.copyWith(ecsEnabled: value),
                          success: value
                              ? l10n.desktopPrivacyEcsOnMessage
                              : l10n.desktopPrivacyEcsOffMessage,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopPrivacyEcsBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashboardChip(
              label: config.ecsEnabled
                  ? l10n.desktopPrivacyEcsOn
                  : l10n.desktopPrivacyEcsOff,
              tone: config.ecsEnabled
                  ? DashboardChipTone.ok
                  : DashboardChipTone.idle,
              dot: true,
            ),
          ),
          const SizedBox(height: 10),
          FilterToggleRow(
            title: l10n.desktopPrivacyEcsStripTitle,
            body: l10n.desktopPrivacyEcsStripBody,
            value: config.ecsStrip,
            onChanged: saving || !config.ecsEnabled
                ? null
                : (value) => unawaited(
                    _save(
                      config.copyWith(ecsStrip: value),
                      success: value
                          ? l10n.desktopPrivacyEcsStripOn
                          : l10n.desktopPrivacyEcsStripOff,
                    ),
                  ),
          ),
          const SizedBox(height: AppGap.md),
          TextFormField(
            controller: _subnet,
            enabled: config.ecsEnabled && !saving,
            decoration: InputDecoration(
              labelText: l10n.desktopPrivacyEcsSubnetLabel,
              helperText: l10n.desktopPrivacyEcsSubnetHelper,
              hintText: '203.0.113.0/24',
            ),
            style: AppTextStyle.callout.of(context).toTabular,
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: config.ecsEnabled && !saving
                  ? () => unawaited(
                      _save(
                        config.copyWith(
                          ecsCustomSubnet: _subnet.text.trim(),
                        ),
                        success: l10n.desktopPrivacyEcsSaved,
                      ),
                    )
                  : null,
              icon: const GlyphIcon(AppGlyphs.check, size: 16),
              label: Text(l10n.desktopPrivacyEcsSave),
            ),
          ),
        ],
      ),
    );
  }
}
