/// Discovery and the mobile profile: DDR, plus the Apple configuration profile clients can fetch.
///
/// The old desktop console's `DDRCard.vue` and `MobileConfigCard.vue` are the blueprint. DDR asks
/// before it is switched on, because a client that does not trust the certificate loses DNS entirely.
/// The reverse-proxy trust that used to share this card is [EncryptedProxyCard]: two independent
/// switches and a text editor made one card needlessly tall.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_encrypted_models.dart';
import 'package:diting_desktop/data/api/desktop_encrypted_providers.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class EncryptedExtrasCard extends ConsumerWidget {
  const EncryptedExtrasCard({
    super.key,
    required this.status,
    required this.saving,
  });

  final DesktopEncryptedStatus status;
  final bool saving;

  Future<void> _configure(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> patch, {
    required String success,
  }) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopEncryptedProvider.notifier)
        .configure(patch);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null ? success : l10n.desktopEncryptedSaveFailed(error.message),
    );
  }

  Future<void> _toggleDdr(BuildContext context, WidgetRef ref, bool enabled) async {
    final l10n = context.l10n;
    if (enabled) {
      final confirmed = await confirmDesktopAction(
        context,
        title: l10n.desktopEncryptedDdrConfirmTitle,
        body: l10n.desktopEncryptedDdrConfirmBody,
        confirmLabel: l10n.desktopEncryptedDdrConfirm,
        destructive: false,
      );
      if (!confirmed || !context.mounted) return;
    }
    await _configure(
      context,
      ref,
      {'ddrEnabled': enabled},
      success: enabled ? l10n.desktopEncryptedDdrOn : l10n.desktopEncryptedDdrOff,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final status = this.status;
    final config = status.config;
    final saving = this.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopEncryptedDdrTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.locate,
            title: l10n.desktopEncryptedDdrTitle,
            leading: [
              DashboardChip(
                label: config.ddrEnabled
                    ? l10n.commonEnabled
                    : l10n.commonDisabled,
                tone: config.ddrEnabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: config.ddrEnabled,
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
                  value: config.ddrEnabled,
                  semanticLabel: l10n.desktopEncryptedDdrTitle,
                  onChanged: (value) =>
                      unawaited(_toggleDdr(context, ref, value)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopEncryptedDdrBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (status.cert.selfSigned) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopEncryptedDdrSelfSignedWarning,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(
                context,
                color: context.colorScheme.warning,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _MobileConfigRow(
            url: ref.read(desktopApiClientProvider).mobileConfigUri(),
          ),
        ],
      ),
    );
  }
}

class _MobileConfigRow extends StatelessWidget {
  const _MobileConfigRow({required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  l10n.desktopEncryptedMobileConfigTitle,
                  style: DashboardText.rowTitle(context),
                ),
                Text(
                  l10n.desktopEncryptedMobileConfigBody,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: DashboardIconButton(
              glyph: AppGlyphs.copy,
              tooltip: MaterialLocalizations.of(context).copyButtonLabel,
              size: 28,
              glyphSize: 15,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: url.toString())),
            ),
          ),
          SizedBox(
            height: 28,
            child: DashboardIconButton(
              glyph: AppGlyphs.openExternal,
              tooltip: l10n.desktopEncryptedMobileConfigOpen,
              size: 28,
              glyphSize: 15,
              onPressed: () => launchUrl(url),
            ),
          ),
        ],
      ),
    );
  }
}
