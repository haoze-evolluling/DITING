/// The LAN web console: the master switch, the port and the URLs to open.
///
/// The old desktop console's `LanWebCard.vue` is the blueprint. The switch sends
/// `configureFirewall: true`, as the console did, so turning the console on also asks for the rule;
/// whether the host actually has a firewall manager is the service's answer, not a guess here.
///
/// The firewall rule and the admin credential are [LanWebAccessCard], because a page of URLs, a port
/// field and a credential block in one card made it taller than the window.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_web_models.dart';
import 'package:diting_desktop/data/api/desktop_web_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_desktop/widgets/desktop_qr_code.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class LanWebCard extends ConsumerStatefulWidget {
  const LanWebCard({super.key, required this.status, required this.saving});

  final DesktopWebStatus status;
  final bool saving;

  @override
  ConsumerState<LanWebCard> createState() => _LanWebCardState();
}

class _LanWebCardState extends ConsumerState<LanWebCard> {
  late final _port = TextEditingController(text: '${widget.status.port}');
  bool _portInvalid = false;

  @override
  void didUpdateWidget(LanWebCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.port == widget.status.port) return;
    _port.text = '${widget.status.port}';
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _configure(bool enabled, {int? port}) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopWebProvider.notifier)
        .configure(enabled: enabled, port: port ?? widget.status.port);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (enabled ? l10n.desktopLanWebOn : l10n.desktopLanWebOff)
          : l10n.desktopLanWebFailed(error.message),
    );
  }

  void _savePort() {
    final port = int.tryParse(_port.text);
    if (port == null || port < 1 || port > 65535) {
      setState(() => _portInvalid = true);
      return;
    }
    setState(() => _portInvalid = false);
    unawaited(_configure(widget.status.enabled, port: port));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = widget.status;
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopLanWebTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.link,
            title: l10n.desktopLanWebTitle,
            leading: [
              DashboardChip(
                label: status.enabled
                    ? l10n.desktopLanWebOpen
                    : l10n.desktopLanWebLocal,
                tone: status.enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: status.enabled,
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
                  value: status.enabled,
                  semanticLabel: l10n.desktopLanWebTitle,
                  onChanged: (value) => unawaited(_configure(value)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            status.enabled
                ? l10n.desktopLanWebEnabledBody
                : l10n.desktopLanWebDisabledBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (status.enabled) ...[
            const SizedBox(height: 12),
            Text(
              l10n.desktopLanWebUrls,
              style: DashboardText.rowTitle(context),
            ),
            const SizedBox(height: 4),
            if (status.webUrls.isEmpty)
              Text(
                l10n.desktopLanWebNoUrls,
                style: DashboardText.label(context),
              )
            else
              for (final url in status.webUrls) _UrlRow(url: url),
            if (status.webUrls.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ScanRow(url: status.webUrls.first),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l10n.desktopLanWebPort,
                    ),
                    style: AppTextStyle.callout.of(context).toTabular,
                    onChanged: (_) => setState(() => _portInvalid = false),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: saving ? null : _savePort,
                  child: Text(l10n.desktopLanWebSavePort),
                ),
              ],
            ),
            if (_portInvalid) ...[
              const SizedBox(height: 6),
              Text(
                l10n.desktopLanWebPortInvalid,
                style: DashboardText.label(
                  context,
                  color: context.colorScheme.error,
                ),
              ),
            ],
          ],
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
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
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
              tooltip: l10n.desktopEncryptedOpenUrl,
              size: 28,
              glyphSize: 15,
              onPressed: () => launchUrl(Uri.parse(url)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The first LAN address as a scannable code: the console's answer to "typing an IP on a phone".
class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      spacing: 12,
      children: [
        DesktopQrCode(
          data: url,
          size: 88,
          semanticLabel: l10n.desktopLanWebQrCaption,
        ),
        Expanded(
          child: Text(
            l10n.desktopLanWebQrCaption,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
        ),
      ],
    );
  }
}
