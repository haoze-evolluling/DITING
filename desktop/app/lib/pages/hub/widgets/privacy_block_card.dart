/// The record-type blocks: ECH, ANY (with its answer mode) and IPv6 answers.
///
/// The old desktop console's `PrivacyPanel.vue` is the blueprint; these three switches left the
/// protocol card because that card stacked two different ideas and grew taller than the window.
/// Every switch saves on the spot and the page re-reads `/status`.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:diting_desktop/data/api/desktop_privacy_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/pages/hub/widgets/privacy_common.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacyBlockCard extends ConsumerWidget {
  const PrivacyBlockCard({
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
      semanticLabel: l10n.desktopPrivacyBlockTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.block,
            title: l10n.desktopPrivacyBlockTitle,
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
            l10n.desktopPrivacyBlockBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
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
