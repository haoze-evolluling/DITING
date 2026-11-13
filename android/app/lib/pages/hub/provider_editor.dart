// ignore_for_file: sort_child_properties_last
// The custom-provider editor dialog: protocol switcher, name, address (or host and port) and the
// bolt button that probes the typed endpoint before saving.
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/native/dns_latency_bridge.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/state/network_tools_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// What the dialog hands back: `address` is the DoH url or `host:port` for DNS and DoT.
class ProviderDraft {
  const ProviderDraft({
    required this.name,
    required this.protocol,
    required this.address,
  });

  final String name;
  final ProviderProtocol protocol;
  final String address;
}

/// One inline probe result, shown under the address field.
class _ProbeOutcome {
  const _ProbeOutcome({required this.ok, required this.text});

  final bool ok;
  final String text;
}

/// Add/edit dialog for a custom provider.
class ProviderEditor extends ConsumerStatefulWidget {
  const ProviderEditor({super.key, required this.protocol, this.initial});

  final ProviderProtocol protocol;
  final MockProvider? initial;

  @override
  ConsumerState<ProviderEditor> createState() => ProviderEditorState();
}

class ProviderEditorState extends ConsumerState<ProviderEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );

  /// DoH only; plain DNS and DoT fill [_host] and [_port] separately.
  late final TextEditingController _address = TextEditingController(
    text: widget.initial?.protocol == ProviderProtocol.doh
        ? widget.initial?.address ?? ''
        : '',
  );
  late final _HostPort _initialHostPort = _splitHostPort(
    widget.initial?.protocol == ProviderProtocol.doh
        ? null
        : widget.initial?.address,
    widget.protocol,
  );
  late final TextEditingController _host = TextEditingController(
    text: _initialHostPort.host,
  );
  late final TextEditingController _port = TextEditingController(
    text: '${_initialHostPort.port}',
  );
  late ProviderProtocol _protocol = widget.protocol;
  String? _error;

  /// Set while the bolt button probes the typed endpoint; [_probe] holds the last answer.
  bool _testing = false;
  _ProbeOutcome? _probe;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.providerMgmtNameRequired);
      return;
    }
    final String address;
    if (_protocol == ProviderProtocol.doh) {
      address = _address.text.trim();
      if (!address.startsWith('https://')) {
        setState(() => _error = context.l10n.providerMgmtDohRequired);
        return;
      }
    } else {
      final host = _stripBrackets(_host.text.trim());
      final port = int.tryParse(_port.text.trim()) ?? 0;
      if (host.isEmpty) {
        setState(() => _error = context.l10n.providerMgmtAddressRequired);
        return;
      }
      if (port < 1 || port > 65535) {
        setState(() => _error = context.l10n.providerMgmtPortRange);
        return;
      }
      address = joinHostPort(host, port);
    }
    Navigator.of(context)
        .pop(ProviderDraft(name: name, protocol: _protocol, address: address));
  }

  /// Drops a stale answer as soon as the endpoint being probed changes.
  void _clearProbe() {
    if (_probe == null && _error == null) return;
    setState(() {
      _probe = null;
      _error = null;
    });
  }

  void _setProbeError(String text) {
    setState(() {
      _testing = false;
      _probe = _ProbeOutcome(ok: false, text: text);
    });
  }

  /// Spec for the endpoint as typed; null (with the reason under the field) when it cannot be
  /// probed yet.
  DnsLatencyProviderSpec? _probeSpec() {
    final name = _name.text.trim();
    if (_protocol == ProviderProtocol.doh) {
      final url = _address.text.trim();
      final host = Uri.tryParse(url)?.host ?? '';
      if (!url.startsWith('https://') || host.isEmpty) {
        _setProbeError(context.l10n.providerMgmtDohRequired);
        return null;
      }
      return DnsLatencyProviderSpec(
        id: 'draft',
        name: name.isEmpty ? 'draft' : name,
        host: host,
        port: 443,
        protocol: DnsLatencyProtocol.doh,
        url: url,
      );
    }
    final host = _stripBrackets(_host.text.trim());
    final port = int.tryParse(_port.text.trim()) ?? 0;
    if (host.isEmpty) {
      _setProbeError(context.l10n.providerMgmtAddressRequired);
      return null;
    }
    if (port < 1 || port > 65535) {
      _setProbeError(context.l10n.providerMgmtPortRange);
      return null;
    }
    return DnsLatencyProviderSpec(
      id: 'draft',
      name: name.isEmpty ? 'draft' : name,
      host: host,
      port: port,
      protocol: _protocol == ProviderProtocol.dot
          ? DnsLatencyProtocol.dot
          : DnsLatencyProtocol.dns,
    );
  }

  /// Probes the typed endpoint once: this only answers "does it work", the latency test page keeps
  /// the multi-attempt averages.
  Future<void> _test() async {
    if (_testing) return;
    final spec = _probeSpec();
    if (spec == null) return;
    setState(() {
      _testing = true;
      _probe = null;
      _error = null;
    });
    final domain = ref.read(latencyDomainProvider);
    try {
      final samples = await ref
          .read(dnsLatencyRunnerProvider)
          .probe(providers: [spec], domain: domain, attempts: 1);
      if (!mounted) return;
      final sample = samples.isEmpty ? null : samples.first;
      setState(() {
        _testing = false;
        _probe = sample != null && sample.success
            ? _ProbeOutcome(
                ok: true,
                text: context.l10n.providerMgmtProbeOk(sample.elapsedMs),
              )
            : _ProbeOutcome(
                ok: false,
                text: context.l10n.providerMgmtProbeFailed(
                  sample?.message ?? context.l10n.providerMgmtProbeNoResponse,
                ),
              );
      });
    } on DnsLatencyUnavailable catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _probe = _ProbeOutcome(
          ok: false,
          text: error.message ?? context.l10n.dnsLatencyUnsupported,
        );
      });
    }
  }

  /// Bolt button in the address field's trailing slot.
  Widget _probeButton() {
    return IconButton(
      tooltip: context.l10n.providerMgmtProbeTooltip,
      onPressed: _testing ? null : _test,
      icon: _testing
          ? const CommonCircleLoading(size: 18)
          : const GlyphIcon(AppGlyphs.bolt, size: 20),
    );
  }

  Widget? _probeLine(BuildContext context) {
    final probe = _probe;
    if (probe == null) return null;
    final color = probe.ok
        ? context.colorScheme.success
        : context.colorScheme.error;
    return Row(
      spacing: 6,
      children: [
        GlyphIcon(
          probe.ok ? AppGlyphs.checkCircle : AppGlyphs.error,
          size: 16,
          color: color,
        ),
        Expanded(
          child: Text(
            probe.text,
            style: AppTextStyle.footnote.of(context).copyWith(color: color),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDoh = _protocol == ProviderProtocol.doh;
    final probeLine = _probeLine(context);
    return CommonDialog(
      title: widget.initial == null ? context.l10n.providerMgmtAdd : context.l10n.providerMgmtEditTitle,
      hasFields: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          SegmentedControl<ProviderProtocol>(
            segments: [
              for (final protocol in ProviderProtocol.values)
                (protocol, protocol.label),
            ],
            value: _protocol,
            onChanged: (value) => setState(() {
              // Switching protocol also swaps in that protocol's default port, unless the user
              // typed a custom one.
              final previousDefault = '${_defaultPortOf(_protocol)}';
              final port = _port.text.trim();
              if (port.isEmpty || port == previousDefault) {
                _port.text = '${_defaultPortOf(value)}';
              }
              _protocol = value;
              _error = null;
              _probe = null;
            }),
          ),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: context.l10n.serverName),
          ),
          if (isDoh) ...[
            TextField(
              controller: _address,
              autocorrect: false,
              onChanged: (_) => _clearProbe(),
              decoration: InputDecoration(
                labelText: context.l10n.providerMgmtDohAddressLabel,
                hintText: 'https://dns.example.com/dns-query',
                suffixIcon: _probeButton(),
              ),
            ),
            ?probeLine,
          ] else ...[
            TextField(
              controller: _host,
              autocorrect: false,
              onChanged: (_) => _clearProbe(),
              decoration: InputDecoration(
                labelText: context.l10n.providerMgmtAddressLabel,
                hintText: '1.1.1.1',
                suffixIcon: _probeButton(),
              ),
            ),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              onChanged: (_) => _clearProbe(),
              decoration: InputDecoration(
                labelText: context.l10n.providerMgmtPortLabel,
                hintText: '${_defaultPortOf(_protocol)}',
              ),
            ),
            ?probeLine,
          ],
          if (_error != null)
            Text(
              _error!,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(onPressed: _save, child: Text(context.l10n.commonSave)),
      ],
    );
  }
}

class _HostPort {
  const _HostPort(this.host, this.port);

  final String host;
  final int port;
}

/// Splits a stored `host:port` for the editor; a missing port falls back to the protocol default.
_HostPort _splitHostPort(String? address, ProviderProtocol protocol) {
  final fallback = _defaultPortOf(protocol);
  final trimmed = address?.trim() ?? '';
  if (trimmed.isEmpty) return _HostPort('', fallback);
  final separator = trimmed.lastIndexOf(':');
  if (separator <= 0) return _HostPort(trimmed, fallback);
  return _HostPort(
    _stripBrackets(trimmed.substring(0, separator)),
    int.tryParse(trimmed.substring(separator + 1)) ?? fallback,
  );
}

int _defaultPortOf(ProviderProtocol protocol) => switch (protocol) {
  ProviderProtocol.dot => 853,
  ProviderProtocol.dns => 53,
  // DoH carries its port inside the URL; 443 is only a placeholder.
  ProviderProtocol.doh => 443,
};

String _stripBrackets(String value) {
  var result = value;
  if (result.startsWith('[')) result = result.substring(1);
  if (result.endsWith(']')) result = result.substring(0, result.length - 1);
  return result;
}
