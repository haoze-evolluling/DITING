/// The protocol-privacy switches: EDE, private PTR, single-label names and EDNS padding.
///
/// The old desktop console's `PrivacyPanel.vue` (first card) is the blueprint. Every switch saves on
/// the spot through `/dns/privacy/configure` (or `/dns/unqualified/configure`), and the page re-reads
/// `/status`, so a rejected change flips back on its own.
///
/// The record-type blocks (ECH, ANY, IPv6) sit beside this card as [PrivacyBlockCard]: one card of
/// seven switches was taller than the window and grouped two different ideas.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:diting_desktop/data/api/desktop_privacy_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/pages/hub/widgets/privacy_common.dart';
import 'package:diting_desktop/widgets/desktop_picker.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacyProtocolCard extends ConsumerWidget {
  const PrivacyProtocolCard({
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
    void privacy(DesktopPrivacyConfig next, String success) => unawaited(
      savePrivacySetting(context, ref, () => notifier.setPrivacy(next), success),
    );
    return DashboardCard(
      semanticLabel: l10n.desktopPrivacyProtocolTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.rules,
            title: l10n.desktopPrivacyProtocolTitle,
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
            l10n.desktopPrivacyProtocolBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          FilterToggleRow(
            title: l10n.desktopPrivacyEdeTitle,
            body: l10n.desktopPrivacyEdeBody,
            value: config.enableEde,
            onChanged: saving
                ? null
                : (value) => privacy(
                    config.copyWith(enableEde: value),
                    value
                        ? l10n.desktopPrivacyEdeOn
                        : l10n.desktopPrivacyEdeOff,
                  ),
          ),
          const SizedBox(height: 8),
          FilterToggleRow(
            title: l10n.desktopPrivacyPtrTitle,
            body: l10n.desktopPrivacyPtrBody,
            value: config.blockPrivatePtr,
            onChanged: saving
                ? null
                : (value) => privacy(
                    config.copyWith(blockPrivatePtr: value),
                    value
                        ? l10n.desktopPrivacyPtrOn
                        : l10n.desktopPrivacyPtrOff,
                  ),
          ),
          const SizedBox(height: 8),
          FilterToggleRow(
            title: l10n.desktopPrivacyUnqualifiedTitle,
            body: l10n.desktopPrivacyUnqualifiedBody,
            value: config.blockUnqualified,
            onChanged: saving
                ? null
                : (value) => unawaited(
                    savePrivacySetting(
                      context,
                      ref,
                      () => notifier.setUnqualified(value),
                      value
                          ? l10n.desktopPrivacyUnqualifiedOn
                          : l10n.desktopPrivacyUnqualifiedOff,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          DashboardBlock(
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        l10n.desktopPrivacyPaddingTitle,
                        style: DashboardText.rowTitle(context),
                      ),
                      Text(
                        l10n.desktopPrivacyPaddingBody,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardText.label(context),
                      ),
                    ],
                  ),
                ),
                DesktopPicker(
                  glyph: AppGlyphs.sliders,
                  semanticLabel: l10n.desktopPrivacyPaddingTitle,
                  label: l10n.desktopPrivacyPaddingValue(config.ednsPadding),
                  active: true,
                  items: [
                    for (final size in {
                      ...desktopEdnsPaddingSizes,
                      config.ednsPadding,
                    })
                      CommonPopupMenuItem(
                        label: l10n.desktopPrivacyPaddingValue(size),
                        checked: size == config.ednsPadding,
                        onPressed: saving
                            ? null
                            : () => privacy(
                                config.copyWith(ednsPadding: size),
                                l10n.desktopPrivacyPaddingSaved,
                              ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
