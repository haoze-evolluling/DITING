/// The encrypted listeners' network parameters: bind address, TLS server name, the three ports and the
/// DoH path.
///
/// The old desktop console's `EncryptedListenersCard.vue` keeps this form under the protocol switches;
/// here it is its own card, because a five-field form plus three switch rows was one card too long.
/// The fields are a draft that saves with the button, and a rejected save keeps what was typed.
library;

import 'dart:async';

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

const double _fieldWidth = 190;

class EncryptedNetworkCard extends ConsumerStatefulWidget {
  const EncryptedNetworkCard({
    super.key,
    required this.status,
    required this.saving,
  });

  final DesktopEncryptedStatus status;
  final bool saving;

  @override
  ConsumerState<EncryptedNetworkCard> createState() =>
      _EncryptedNetworkCardState();
}

class _EncryptedNetworkCardState extends ConsumerState<EncryptedNetworkCard> {
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
  void didUpdateWidget(EncryptedNetworkCard oldWidget) {
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

  void _save() {
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
    unawaited(_configure(
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
    ));
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

  void _reset() {
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
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopEncryptedNetworkTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.connections,
            title: l10n.desktopEncryptedNetworkTitle,
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
            l10n.desktopEncryptedServerNameHint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
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
                onPressed: saving ? null : _reset,
                child: Text(l10n.desktopEncryptedReset),
              ),
              FilledButton.tonal(
                onPressed: saving ? null : _save,
                child: Text(l10n.desktopEncryptedSaveNetwork),
              ),
            ],
          ),
        ],
      ),
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
        style: AppTextStyle.callout.of(context).toTabular,
        onChanged: (_) => onChanged(),
      ),
    );
  }
}
