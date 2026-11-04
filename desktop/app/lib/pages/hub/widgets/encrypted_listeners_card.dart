/// The encrypted DNS listeners: the master switch, the three protocols with their real listen state,
/// and the DoH URLs a client can be given.
///
/// The old desktop console's `EncryptedListenersCard.vue` is the blueprint. A configured port is not
/// a bound port, so each protocol shows both. The network parameters are a draft that saves with its
/// own button, so they are [EncryptedNetworkCard]: one card holding both the switches and a five-field
/// form grew taller than the window.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_encrypted_models.dart';
import 'package:diting_desktop/data/api/desktop_encrypted_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class EncryptedListenersCard extends ConsumerWidget {
  const EncryptedListenersCard({
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final config = status.config;
    final saving = this.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopEncryptedListenersTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.lock,
            title: l10n.desktopEncryptedListenersTitle,
            leading: [
              DashboardChip(
                label: config.enabled
                    ? l10n.desktopEncryptedEnabled
                    : l10n.desktopEncryptedDisabled,
                tone: config.enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: config.enabled,
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
                  value: config.enabled,
                  semanticLabel: l10n.desktopEncryptedListenersTitle,
                  onChanged: (value) => _configure(
                    context,
                    ref,
                    {'enabled': value},
                    success: value
                        ? l10n.desktopEncryptedOn
                        : l10n.desktopEncryptedOff,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopEncryptedListenersBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (config.enabled && !config.anyProtocol) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopEncryptedNoProtocol,
              style: DashboardText.label(
                context,
                color: context.colorScheme.warning,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _ProtocolRow(
            title: l10n.desktopEncryptedDot,
            body: l10n.desktopEncryptedDotBody(config.effectiveDotPort),
            live: config.dotEnabled,
            listen: status.dotListen,
            onChanged: saving
                ? null
                : (value) => _configure(
                    context,
                    ref,
                    {'dotEnabled': value},
                    success: value
                        ? l10n.desktopEncryptedDotOn
                        : l10n.desktopEncryptedDotOff,
                  ),
          ),
          const SizedBox(height: 6),
          _ProtocolRow(
            title: l10n.desktopEncryptedDoh,
            body: l10n.desktopEncryptedDohBody(
              config.effectiveDohPort,
              config.effectiveDohPath,
            ),
            live: config.dohEnabled,
            listen: status.dohListen,
            onChanged: saving
                ? null
                : (value) => _configure(
                    context,
                    ref,
                    {'dohEnabled': value},
                    success: value
                        ? l10n.desktopEncryptedDohOn
                        : l10n.desktopEncryptedDohOff,
                  ),
          ),
          if (config.dohEnabled && status.dohUrls.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l10n.desktopEncryptedUrls,
              style: DashboardText.label(context),
            ),
            const SizedBox(height: 4),
            for (final url in status.dohUrls) _UrlRow(url: url),
          ],
          const SizedBox(height: 6),
          _ProtocolRow(
            title: l10n.desktopEncryptedDoq,
            body: l10n.desktopEncryptedDoqBody(config.effectiveDoqPort),
            live: config.doqEnabled,
            listen: status.doqListen,
            onChanged: saving
                ? null
                : (value) => _configure(
                    context,
                    ref,
                    {'doqEnabled': value},
                    success: value
                        ? l10n.desktopEncryptedDoqOn
                        : l10n.desktopEncryptedDoqOff,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProtocolRow extends StatelessWidget {
  const _ProtocolRow({
    required this.title,
    required this.body,
    required this.live,
    required this.listen,
    required this.onChanged,
  });

  final String title;
  final String body;
  final bool live;
  final String listen;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final listening = listen.isNotEmpty;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
                if (live)
                  Text(
                    listening
                        ? l10n.desktopEncryptedListening(listen)
                        : l10n.desktopEncryptedNotListening,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.label(
                      context,
                      color: listening
                          ? colorScheme.success
                          : colorScheme.warning,
                    ),
                  ),
              ],
            ),
          ),
          DashboardSwitch(
            value: live,
            semanticLabel: title,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _UrlRow extends StatelessWidget {
  const _UrlRow({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 6,
      children: [
        Expanded(
          child: Text(
            url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context).toTabular,
          ),
        ),
        SizedBox(
          height: 28,
          child: DashboardIconButton(
            glyph: AppGlyphs.copy,
            tooltip: MaterialLocalizations.of(context).copyButtonLabel,
            size: 28,
            glyphSize: 15,
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          ),
        ),
        SizedBox(
          height: 28,
          child: DashboardIconButton(
            glyph: AppGlyphs.openExternal,
            tooltip: context.l10n.desktopEncryptedOpenUrl,
            size: 28,
            glyphSize: 15,
            onPressed: () => launchUrl(Uri.parse(url)),
          ),
        ),
      ],
    );
  }
}
