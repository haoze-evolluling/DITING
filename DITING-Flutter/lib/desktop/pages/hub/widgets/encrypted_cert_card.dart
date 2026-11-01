/// The server certificate: its summary, its expiry warning and the two ways to replace it (generate a
/// self-signed one, or import a PEM pair).
///
/// The old desktop console's `CertificateCard.vue` is the blueprint. Nothing here reads key material
/// back: the service exposes a summary only.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_encrypted_models.dart';
import 'package:diting/desktop/data/api/desktop_encrypted_providers.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/desktop/widgets/desktop_picker.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const List<String> desktopCertKeyTypes = ['ecdsa', 'rsa'];

class EncryptedCertCard extends ConsumerWidget {
  const EncryptedCertCard({
    super.key,
    required this.status,
    required this.saving,
  });

  final DesktopEncryptedStatus status;
  final bool saving;

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final params = await showFloatingDialog<Map<String, Object?>>(
      context: context,
      child: _GenerateCertDialog(config: status.config),
    );
    if (params == null || !context.mounted) return;
    final error = await ref
        .read(desktopEncryptedProvider.notifier)
        .generateCert(params);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopEncryptedCertGenerated
          : l10n.desktopEncryptedSaveFailed(error.message),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final pair = await showFloatingDialog<({String cert, String key})>(
      context: context,
      child: const _ImportCertDialog(),
    );
    if (pair == null || !context.mounted) return;
    final error = await ref
        .read(desktopEncryptedProvider.notifier)
        .importCert(certPem: pair.cert, keyPem: pair.key);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopEncryptedCertImported
          : l10n.desktopEncryptedSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final cert = status.cert;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopEncryptedCertTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.verified,
            title: l10n.desktopEncryptedCertTitle,
            leading: [
              DashboardChip(
                label: cert.loaded
                    ? (cert.selfSigned
                          ? l10n.desktopEncryptedCertSelfSigned
                          : l10n.desktopEncryptedCertLoaded)
                    : l10n.desktopEncryptedCertMissing,
                tone: cert.loaded
                    ? DashboardChipTone.ok
                    : DashboardChipTone.warn,
                dot: cert.loaded,
              ),
            ],
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
            l10n.desktopEncryptedCertBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (status.certExpired || status.certExpiresSoon) ...[
            const SizedBox(height: 8),
            Text(
              status.certExpired
                  ? l10n.desktopEncryptedCertExpired
                  : l10n.desktopEncryptedCertExpiresSoon,
              style: DashboardText.label(
                context,
                color: status.certExpired
                    ? colorScheme.error
                    : colorScheme.warning,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (!cert.loaded)
            Text(
              cert.error.isEmpty
                  ? l10n.desktopEncryptedCertMissingBody
                  : cert.error,
              style: DashboardText.label(context),
            )
          else ...[
            _Row(label: l10n.desktopEncryptedCertSubject, value: cert.subject),
            _Row(label: l10n.desktopEncryptedCertIssuer, value: cert.issuer),
            _Row(
              label: l10n.desktopEncryptedCertNotAfter,
              value: cert.notAfter,
            ),
            _Row(
              label: l10n.desktopEncryptedCertDays,
              value: l10n.desktopEncryptedCertDaysValue(cert.daysRemaining),
            ),
            if (cert.dnsNames.isNotEmpty)
              _Row(
                label: l10n.desktopEncryptedCertDns,
                value: cert.dnsNames.join(', '),
              ),
            if (cert.ipAddresses.isNotEmpty)
              _Row(
                label: l10n.desktopEncryptedCertIps,
                value: cert.ipAddresses.join(', '),
              ),
            if (cert.fingerprint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                spacing: 6,
                children: [
                  Expanded(
                    child: Text(
                      l10n.desktopEncryptedCertFingerprint(cert.fingerprint),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardText.label(context).toMonospace,
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: DashboardIconButton(
                      glyph: AppGlyphs.copy,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).copyButtonLabel,
                      size: 28,
                      glyphSize: 15,
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: cert.fingerprint),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (status.certDir.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                l10n.desktopEncryptedCertDir(status.certDir),
                style: DashboardText.label(context).toMonospace,
              ),
            ],
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => unawaited(_import(context, ref)),
                child: Text(l10n.desktopEncryptedCertImport),
              ),
              FilledButton.tonal(
                onPressed: saving
                    ? null
                    : () => unawaited(_generate(context, ref)),
                child: Text(l10n.desktopEncryptedCertGenerate),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenerateCertDialog extends StatefulWidget {
  const _GenerateCertDialog({required this.config});

  final DesktopEncryptedConfig config;

  @override
  State<_GenerateCertDialog> createState() => _GenerateCertDialogState();
}

class _GenerateCertDialogState extends State<_GenerateCertDialog> {
  late final _commonName = TextEditingController(
    text: widget.config.certCommonName.isEmpty
        ? widget.config.serverName
        : widget.config.certCommonName,
  );
  late final _dnsNames = TextEditingController(
    text: widget.config.certDnsNames.join('\n'),
  );
  late final _ips = TextEditingController(
    text: widget.config.certIpAddresses.join('\n'),
  );
  late final _days = TextEditingController(
    text: '${widget.config.certValidDays > 0 ? widget.config.certValidDays : 365}',
  );
  String _keyType = desktopCertKeyTypes.first;

  @override
  void initState() {
    super.initState();
    if (widget.config.certKeyType == 'rsa') _keyType = 'rsa';
  }

  @override
  void dispose() {
    _commonName.dispose();
    _dnsNames.dispose();
    _ips.dispose();
    _days.dispose();
    super.dispose();
  }

  List<String> _lines(TextEditingController controller) => [
    for (final line in controller.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final days = int.tryParse(_days.text) ?? 0;
    return CommonDialog(
      title: l10n.desktopEncryptedCertGenerateTitle,
      hasFields: true,
      width: 580,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: days <= 0
              ? null
              : () => popFloatingDialog(context, {
                  'keyType': _keyType,
                  'commonName': _commonName.text.trim(),
                  'dnsNames': _lines(_dnsNames),
                  'ipAddresses': _lines(_ips),
                  'validDays': days,
                  'force': true,
                }),
          child: Text(l10n.desktopEncryptedCertGenerateConfirm),
        ),
      ],
      child: SizedBox(
        width: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              l10n.desktopEncryptedCertGenerateBody,
              style: DashboardText.label(context),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.desktopEncryptedCertKeyType,
                  style: DashboardText.rowTitle(context),
                ),
                DesktopPicker(
                  glyph: AppGlyphs.key,
                  semanticLabel: l10n.desktopEncryptedCertKeyType,
                  label: _keyType,
                  active: true,
                  items: [
                    for (final type in desktopCertKeyTypes)
                      CommonPopupMenuItem(
                        label: type,
                        checked: type == _keyType,
                        onPressed: () => setState(() => _keyType = type),
                      ),
                  ],
                ),
              ],
            ),
            TextFormField(
              controller: _commonName,
              decoration: InputDecoration(
                labelText: l10n.desktopEncryptedCertCommonName,
              ),
              style: AppTextStyle.callout.of(context),
            ),
            TextFormField(
              controller: _dnsNames,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.desktopEncryptedCertDnsNames,
              ),
              style: AppTextStyle.callout.of(context).toMonospace,
            ),
            TextFormField(
              controller: _ips,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.desktopEncryptedCertIpAddresses,
              ),
              style: AppTextStyle.callout.of(context).toMonospace,
            ),
            SizedBox(
              width: 190,
              child: TextFormField(
                controller: _days,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.desktopEncryptedCertValidDays,
                ),
                style: AppTextStyle.callout.of(context),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportCertDialog extends StatefulWidget {
  const _ImportCertDialog();

  @override
  State<_ImportCertDialog> createState() => _ImportCertDialogState();
}

class _ImportCertDialogState extends State<_ImportCertDialog> {
  final _cert = TextEditingController();
  final _key = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _cert.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: l10n.desktopEncryptedCertImportTitle,
      hasFields: true,
      width: 620,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () {
            if (_cert.text.trim().isEmpty || _key.text.trim().isEmpty) {
              setState(() => _invalid = true);
              return;
            }
            popFloatingDialog(context, (
              cert: _cert.text,
              key: _key.text,
            ));
          },
          child: Text(l10n.desktopEncryptedCertImportConfirm),
        ),
      ],
      child: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              l10n.desktopEncryptedCertImportBody,
              style: DashboardText.label(context),
            ),
            TextField(
              controller: _cert,
              minLines: 4,
              maxLines: 8,
              style: AppTextStyle.callout.of(context).toMonospace,
              decoration: InputDecoration(
                labelText: l10n.desktopEncryptedCertPem,
              ),
            ),
            TextField(
              controller: _key,
              minLines: 4,
              maxLines: 8,
              style: AppTextStyle.callout.of(context).toMonospace,
              decoration: InputDecoration(
                labelText: l10n.desktopEncryptedKeyPem,
              ),
            ),
            if (_invalid)
              Text(
                l10n.desktopEncryptedCertImportInvalid,
                style: DashboardText.label(
                  context,
                  color: context.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
