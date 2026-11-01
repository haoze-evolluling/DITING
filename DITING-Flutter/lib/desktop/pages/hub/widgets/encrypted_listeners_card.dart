/// The encrypted DNS listeners: the master switch, the three protocols with their real listen state,
/// the network parameters and the DoH URLs a client can be given.
///
/// The old desktop console's `EncryptedListenersCard.vue` is the blueprint. A configured port is not
/// a bound port, so each protocol shows both. Switches save one field each; the network parameters
/// are a draft that saves with its button.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_encrypted_models.dart';
import 'package:diting/desktop/data/api/desktop_encrypted_providers.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

const double _fieldWidth = 190;

class EncryptedListenersCard extends ConsumerStatefulWidget {
  const EncryptedListenersCard({
    super.key,
    required this.status,
    required this.saving,
  });

  final DesktopEncryptedStatus status;
  final bool saving;

  @override
  ConsumerState<EncryptedListenersCard> createState() =>
      _EncryptedListenersCardState();
}

class _EncryptedListenersCardState
    extends ConsumerState<EncryptedListenersCard> {
  final _listen = TextEditingController();
  final _serverName = TextEditingController();
  final _dotPort = TextEditingController();
  final _dohPort = TextEditingController();
  final _doqPort = TextEditingController();
  final _dohPath = TextEditingController();
  DesktopEncryptedStatus? _adopted;
  bool _dirty = false;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.status);
  }

  @override
  void didUpdateWidget(EncryptedListenersCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.status);
  }

  @override
  void dispose() {
    _listen.dispose();
    _serverName.dispose();
    _dotPort.dispose();
    _dohPort.dispose();
    _doqPort.dispose();
    _dohPath.dispose();
    super.dispose();
  }

  void _adopt(DesktopEncryptedStatus status) {
    if (identical(_adopted, status)) return;
    _adopted = status;
    if (_dirty) return;
    _applyNetwork(status.config);
  }

  void _applyNetwork(DesktopEncryptedConfig config) {
    _listen.text = config.listenAddress;
    _serverName.text = config.serverName;
    _dotPort.text = '${config.effectiveDotPort}';
    _dohPort.text = '${config.effectiveDohPort}';
    _doqPort.text = '${config.effectiveDoqPort}';
    _dohPath.text = config.effectiveDohPath;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

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

  void _saveNetwork() {
    final l10n = context.l10n;
    final dot = int.tryParse(_dotPort.text);
    final doh = int.tryParse(_dohPort.text);
    final doq = int.tryParse(_doqPort.text);
    bool portOk(int? port) => port != null && port > 0 && port <= 65535;
    if (!portOk(dot) || !portOk(doh) || !portOk(doq)) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    unawaited(
      _configure(
        {
          'listenAddress': _listen.text.trim(),
          'serverName': _serverName.text.trim(),
          'dotPort': dot,
          'dohPort': doh,
          'doqPort': doq,
          'dohPath': _dohPath.text.trim(),
        },
        success: l10n.desktopEncryptedNetworkSaved,
        fromForm: true,
      ),
    );
  }

  void _resetNetwork() {
    setState(() {
      _dirty = false;
      _listen.text = '';
      _serverName.text = '';
      _dotPort.text = '${widget.status.defaultDotPort}';
      _dohPort.text = '${widget.status.defaultDohPort}';
      _doqPort.text = '${widget.status.defaultDoqPort}';
      _dohPath.text = widget.status.defaultDohPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = widget.status;
    final config = status.config;
    final saving = widget.saving;
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
                  onChanged: (value) => unawaited(
                    _configure(
                      {'enabled': value},
                      success: value
                          ? l10n.desktopEncryptedOn
                          : l10n.desktopEncryptedOff,
                    ),
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
                : (value) => unawaited(
                    _configure(
                      {'dotEnabled': value},
                      success: value
                          ? l10n.desktopEncryptedDotOn
                          : l10n.desktopEncryptedDotOff,
                    ),
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
                : (value) => unawaited(
                    _configure(
                      {'dohEnabled': value},
                      success: value
                          ? l10n.desktopEncryptedDohOn
                          : l10n.desktopEncryptedDohOff,
                    ),
                  ),
          ),
          if (config.dohEnabled && status.dohUrls.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l10n.desktopEncryptedUrls,
              style: DashboardText.label(context),
            ),
            const SizedBox(height: 4),
            for (final url in status.dohUrls)
              _UrlRow(url: url),
          ],
          const SizedBox(height: 6),
          _ProtocolRow(
            title: l10n.desktopEncryptedDoq,
            body: l10n.desktopEncryptedDoqBody(config.effectiveDoqPort),
            live: config.doqEnabled,
            listen: status.doqListen,
            onChanged: saving
                ? null
                : (value) => unawaited(
                    _configure(
                      {'doqEnabled': value},
                      success: value
                          ? l10n.desktopEncryptedDoqOn
                          : l10n.desktopEncryptedDoqOff,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.desktopEncryptedNetworkTitle,
            style: DashboardText.rowTitle(context),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Field(
                label: l10n.desktopEncryptedListenAddress,
                controller: _listen,
                hint: l10n.desktopEncryptedListenHint,
                onChanged: _markDirty,
              ),
              _Field(
                label: l10n.desktopEncryptedServerName,
                controller: _serverName,
                hint: 'dns.lan',
                onChanged: _markDirty,
              ),
              _Field(
                label: l10n.desktopEncryptedDotPort,
                controller: _dotPort,
                onChanged: _markDirty,
                number: true,
              ),
              _Field(
                label: l10n.desktopEncryptedDohPort,
                controller: _dohPort,
                onChanged: _markDirty,
                number: true,
              ),
              _Field(
                label: l10n.desktopEncryptedDoqPort,
                controller: _doqPort,
                onChanged: _markDirty,
                number: true,
              ),
              _Field(
                label: l10n.desktopEncryptedDohPath,
                controller: _dohPath,
                hint: '/dns-query',
                onChanged: _markDirty,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopEncryptedServerNameHint,
            style: DashboardText.label(context),
          ),
          if (_invalid) ...[
            const SizedBox(height: 6),
            Text(
              l10n.desktopEncryptedPortInvalid,
              style: DashboardText.label(
                context,
                color: context.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: saving ? null : _resetNetwork,
                child: Text(l10n.desktopEncryptedReset),
              ),
              FilledButton.tonal(
                onPressed: saving ? null : _saveNetwork,
                child: Text(l10n.desktopEncryptedSaveNetwork),
              ),
            ],
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
            style: DashboardText.label(context).toMonospace,
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.number = false,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? hint;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _fieldWidth,
      child: TextFormField(
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(labelText: label, hintText: hint),
        style: AppTextStyle.callout.of(context).toMonospace,
        onChanged: (_) => onChanged(),
      ),
    );
  }
}
