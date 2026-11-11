/// The rewrite engine switch and its default lifetime. The switch saves the moment it moves; the
/// number saves with the button next to it, exactly like `RewritePanel.vue`.
///
/// Both writes go through the page's provider, which re-reads the service afterwards, so a rejected
/// value leaves the switch where the service still has it.
library;

import 'dart:async';

import 'package:diting_desktop/widgets/desktop_spacing.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_rewrite_models.dart';
import 'package:diting_desktop/data/api/desktop_rewrite_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Wide enough for `86400`; a desktop window never needs it to shrink.
const double _numberWidth = 190;

class RewriteEngineCard extends ConsumerStatefulWidget {
  const RewriteEngineCard({
    super.key,
    required this.config,
    required this.saving,
  });

  final DesktopRewriteConfig config;
  final bool saving;

  @override
  ConsumerState<RewriteEngineCard> createState() => _RewriteEngineCardState();
}

class _RewriteEngineCardState extends ConsumerState<RewriteEngineCard> {
  /// The TTL as typed. Empty until the first answer arrives, so a later re-read never overwrites a
  /// number that is being edited.
  String _ttl = '';
  bool _invalid = false;

  Future<void> _toggle(bool enabled) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopRewriteProvider.notifier)
        .setEnabled(enabled);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (enabled
                ? l10n.desktopRewriteToggleOn
                : l10n.desktopRewriteToggleOff)
          : l10n.desktopRewriteSaveFailed(error.message),
    );
  }

  Future<void> _saveTtl() async {
    final l10n = context.l10n;
    final ttl = int.tryParse(_ttl);
    if (ttl == null || ttl <= 0) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    final error = await ref.read(desktopRewriteProvider.notifier).setTtl(ttl);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopRewriteTtlSaved
          : l10n.desktopRewriteSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = widget.config;
    if (_ttl.isEmpty) _ttl = '${config.effectiveTtl}';
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopRewriteEngineTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.sliders,
            title: l10n.desktopRewriteEngineTitle,
            leading: [
              DashboardChip(
                label: config.enabled
                    ? l10n.desktopRewriteEngineOn
                    : l10n.desktopRewriteEngineOff,
                tone: config.enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: true,
              ),
            ],
            trailing: [
              DashboardSwitch(
                value: config.enabled,
                semanticLabel: l10n.desktopRewriteEngineTitle,
                onChanged: widget.saving ? null : (value) => _toggle(value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.desktopRewriteEngineBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: AppGap.sm,
            runSpacing: AppGap.field,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: _numberWidth,
                child: TextFormField(
                  initialValue: _ttl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.desktopRewriteDefaultTtl,
                  ),
                  style: AppTextStyle.callout.of(context),
                  onChanged: (value) {
                    _ttl = value;
                    if (_invalid) setState(() => _invalid = false);
                  },
                ),
              ),
              TonalButton(
                size: TonalButtonSize.compact,
                label: l10n.desktopRewriteTtlSave,
                onPressed: widget.saving ? null : () => unawaited(_saveTtl()),
              ),
            ],
          ),
          if (_invalid) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopRewriteTtlInvalid,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
