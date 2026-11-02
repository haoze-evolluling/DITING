/// The protocol-privacy switches: EDE, private PTR, single-label names, ECH, ANY and EDNS padding.
///
/// The old desktop console's `PrivacyPanel.vue` (first card) is the blueprint. Every switch saves on
/// the spot through `/dns/privacy/configure` (or `/dns/unqualified/configure`), and the page re-reads
/// `/status`, so a rejected change flips back on its own.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:diting_desktop/data/api/desktop_privacy_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
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

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    Future<Object?> Function() write,
    String success,
  ) async {
    final l10n = context.l10n;
    final error = await write();
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? success
          : l10n.desktopPrivacySaveFailed('$error'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifier = ref.read(desktopPrivacyProvider.notifier);
    void privacy(DesktopPrivacyConfig next, String success) => unawaited(
      _save(context, ref, () => notifier.setPrivacy(next), success),
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
                    _save(
                      context,
                      ref,
                      () => notifier.setUnqualified(value),
                      value
                          ? l10n.desktopPrivacyUnqualifiedOn
                          : l10n.desktopPrivacyUnqualifiedOff,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          FilterToggleRow(
            title: l10n.desktopPrivacyEchTitle,
            body: l10n.desktopPrivacyEchBody,
            value: config.blockEch,
            onChanged: saving
                ? null
                : (value) => privacy(
                    config.copyWith(blockEch: value),
                    value
                        ? l10n.desktopPrivacyEchOn
                        : l10n.desktopPrivacyEchOff,
                  ),
          ),
          const SizedBox(height: 8),
          FilterToggleRow(
            title: l10n.desktopPrivacyAnyTitle,
            body: l10n.desktopPrivacyAnyBody,
            value: config.blockAny,
            onChanged: saving
                ? null
                : (value) => privacy(
                    config.copyWith(blockAny: value),
                    value
                        ? l10n.desktopPrivacyAnyOn
                        : l10n.desktopPrivacyAnyOff,
                  ),
          ),
          if (config.blockAny) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopPrivacyAnyModeLabel,
              style: DashboardText.rowTitle(context),
            ),
            const SizedBox(height: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                for (final mode in desktopAnyModes)
                  _AnyModeTile(
                    mode: mode,
                    selected: config.effectiveAnyMode == mode,
                    onPressed: saving
                        ? null
                        : () => privacy(
                            config.copyWith(blockAnyMode: mode),
                            l10n.desktopPrivacyAnyModeSaved,
                          ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          FilterToggleRow(
            title: l10n.desktopPrivacyIpv6Title,
            body: l10n.desktopPrivacyIpv6Body,
            value: config.blockIpv6,
            onChanged: saving
                ? null
                : (value) => privacy(
                    config.copyWith(blockIpv6: value),
                    value
                        ? l10n.desktopPrivacyIpv6On
                        : l10n.desktopPrivacyIpv6Off,
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

class _AnyModeTile extends StatelessWidget {
  const _AnyModeTile({
    required this.mode,
    required this.selected,
    required this.onPressed,
  });

  final String mode;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final foreground = selected ? colorScheme.onPrimary : null;
    return CommonCard(
      isSelected: selected,
      fillsSelection: true,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: GlyphIcon(
              selected ? AppGlyphs.checkCircle : AppGlyphs.picker,
              size: 18,
              color: foreground,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  mode == 'rfc8482'
                      ? l10n.desktopPrivacyAnyModeRfc
                      : l10n.desktopPrivacyAnyModeNotimp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(
                    context,
                  ).copyWith(color: foreground),
                ),
                Text(
                  mode == 'rfc8482'
                      ? l10n.desktopPrivacyAnyModeRfcBody
                      : l10n.desktopPrivacyAnyModeNotimpBody,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(
                    context,
                    color: selected
                        ? colorScheme.onPrimary.withValues(alpha: 0.85)
                        : null,
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
