/// Discovery, reverse-proxy trust and the mobile profile: the three small encrypted-DNS extras.
///
/// The old desktop console's `DDRCard.vue`, `ReverseProxyCard.vue` and `MobileConfigCard.vue` are the
/// blueprint. DDR asks before it is switched on, because a client that does not trust the certificate
/// loses DNS entirely.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_encrypted_models.dart';
import 'package:diting/desktop/data/api/desktop_encrypted_providers.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class EncryptedExtrasCard extends ConsumerStatefulWidget {
  const EncryptedExtrasCard({
    super.key,
    required this.status,
    required this.saving,
  });

  final DesktopEncryptedStatus status;
  final bool saving;

  @override
  ConsumerState<EncryptedExtrasCard> createState() =>
      _EncryptedExtrasCardState();
}

class _EncryptedExtrasCardState extends ConsumerState<EncryptedExtrasCard> {
  final _sources = TextEditingController();
  final _header = TextEditingController();
  DesktopEncryptedStatus? _adopted;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.status);
  }

  @override
  void didUpdateWidget(EncryptedExtrasCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.status);
  }

  @override
  void dispose() {
    _sources.dispose();
    _header.dispose();
    super.dispose();
  }

  void _adopt(DesktopEncryptedStatus status) {
    if (identical(_adopted, status)) return;
    _adopted = status;
    if (_dirty) return;
    _sources.text = status.config.proxyTrustedSources.join('\n');
    _header.text = status.config.proxyClientIpHeader;
  }

  List<String> get _parsedSources => [
    for (final line in _sources.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  Future<void> _configure(
    Map<String, Object?> patch, {
    required String success,
    bool fromForm = false,
  }) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopEncryptedProvider.notifier)
        .configure(patch);
    if (!mounted) return;
    if (error == null && fromForm) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null ? success : l10n.desktopEncryptedSaveFailed(error.message),
    );
  }

  Future<void> _toggleDdr(bool enabled) async {
    final l10n = context.l10n;
    if (enabled) {
      final confirmed = await confirmDesktopAction(
        context,
        title: l10n.desktopEncryptedDdrConfirmTitle,
        body: l10n.desktopEncryptedDdrConfirmBody,
        confirmLabel: l10n.desktopEncryptedDdrConfirm,
        destructive: false,
      );
      if (!confirmed || !mounted) return;
    }
    await _configure(
      {'ddrEnabled': enabled},
      success: enabled ? l10n.desktopEncryptedDdrOn : l10n.desktopEncryptedDdrOff,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = widget.status;
    final config = status.config;
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopEncryptedExtrasTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.locate,
            title: l10n.desktopEncryptedExtrasTitle,
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
            l10n.desktopEncryptedExtrasBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          FilterToggleRow(
            title: l10n.desktopEncryptedDdrTitle,
            body: l10n.desktopEncryptedDdrBody,
            value: config.ddrEnabled,
            warning: status.cert.selfSigned
                ? l10n.desktopEncryptedDdrSelfSignedWarning
                : null,
            onChanged: saving ? null : (value) => unawaited(_toggleDdr(value)),
          ),
          const SizedBox(height: 8),
          FilterToggleRow(
            title: l10n.desktopEncryptedProxyTitle,
            body: l10n.desktopEncryptedProxyBody,
            value: config.proxyEnabled,
            warning: status.unrestrictedTrust
                ? l10n.desktopEncryptedProxyUnrestricted
                : null,
            onChanged: saving
                ? null
                : (value) => unawaited(
                    _configure(
                      {'reverseProxy': {'enabled': value}},
                      success: value
                          ? l10n.desktopEncryptedProxyOn
                          : l10n.desktopEncryptedProxyOff,
                    ),
                  ),
          ),
          if (config.proxyEnabled) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopEncryptedProxySources,
              style: DashboardText.rowTitle(context),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _sources,
              minLines: 3,
              maxLines: 6,
              style: AppTextStyle.callout.of(context).toMonospace,
              decoration: InputDecoration(
                hintText: '192.168.1.0/24\n10.0.0.1',
              ),
              onChanged: (_) => setState(() => _dirty = true),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _header,
              decoration: InputDecoration(
                labelText: l10n.desktopEncryptedProxyHeader,
                hintText: 'CF-Connecting-IP',
              ),
              style: AppTextStyle.callout.of(context).toMonospace,
              onChanged: (_) => setState(() => _dirty = true),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                onPressed: saving
                    ? null
                    : () => unawaited(
                        _configure(
                          {
                            'reverseProxy': {
                              'enabled': true,
                              'trustedSources': _parsedSources,
                              'clientIpHeader': _header.text.trim(),
                            },
                          },
                          success: l10n.desktopEncryptedProxySaved,
                          fromForm: true,
                        ),
                      ),
                child: Text(l10n.desktopEncryptedProxySave),
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
