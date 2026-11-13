import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/server/dns_server_config.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Add/edit custom upstream dialog (upstream `AddUpstreamDialog`). Validation reuses
/// [validateServerUpstream] so it cannot drift; a failure keeps the dialog open with the
/// reason under the field.
class UpstreamDialog extends StatefulWidget {
  const UpstreamDialog({super.key, this.initial, required this.protocol});

  final ServerUpstream? initial;

  final DnsProtocol protocol;

  @override
  State<UpstreamDialog> createState() => _UpstreamDialogState();
}

class _UpstreamDialogState extends State<UpstreamDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _address = TextEditingController(
    text: widget.initial?.address ?? '',
  );
  late final _port = TextEditingController(
    text: '${widget.initial?.port ?? _defaultPort(widget.protocol)}',
  );
  late DnsProtocol _protocol = widget.initial?.protocol ?? widget.protocol;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _port.dispose();
    super.dispose();
  }

  static int _defaultPort(DnsProtocol protocol) =>
      protocol == DnsProtocol.dot ? 853 : 53;

  void _submit() {
    final port = int.tryParse(_port.text.trim()) ?? 0;
    final validation = validateServerUpstream(
      name: _name.text,
      protocol: _protocol,
      address: _address.text,
      port: port,
    );
    if (validation is UpstreamInvalid) {
      setState(() => _error = validation.message);
      return;
    }
    final existing = widget.initial;
    Navigator.of(context).pop(
      ServerUpstream(
        id: existing?.id ?? '',
        name: _name.text.trim(),
        protocol: _protocol,
        address: _address.text.trim(),
        port: _protocol == DnsProtocol.doh ? 443 : port,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDoh = _protocol == DnsProtocol.doh;
    return CommonDialog(
      title: widget.initial == null ? context.l10n.serverAddCustom : context.l10n.serverEditCustom,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.configCancel),
        ),
        TextButton(onPressed: _submit, child: Text(context.l10n.serverSave)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          SegmentedControl<DnsProtocol>(
            segments: const [
              (DnsProtocol.dns, 'DNS'),
              (DnsProtocol.doh, 'DoH'),
              (DnsProtocol.dot, 'DoT'),
            ],
            value: _protocol,
            onChanged: (value) => setState(() {
              _protocol = value;
              // Switching protocol also swaps in that protocol's default port.
              _port.text = '${_defaultPort(value)}';
              _error = null;
            }),
          ),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: context.l10n.serverName),
          ),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: isDoh ? context.l10n.serverDohAddress : context.l10n.serverAddress,
              helperText: isDoh
                  ? context.l10n.serverDohPrefix
                  : context.l10n.serverAddressHint,
            ),
          ),
          if (!isDoh)
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.serverPort,
                helperText: context.l10n.serverPortHint,
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: context.listCaptionStyle.copyWith(
                color: context.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
