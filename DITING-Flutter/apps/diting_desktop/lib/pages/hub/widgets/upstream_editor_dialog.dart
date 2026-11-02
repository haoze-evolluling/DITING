/// Add/edit one upstream provider. The behaviour is `UpstreamEditModal.vue`: provider and protocol
/// presets fill the form, a pasted `sdns://` stamp fills protocol/address/URL/fingerprint, and a DoH
/// or DoH3 URL is required and must be a valid https URL.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_upstream_models.dart';
import 'package:diting_desktop/pages/hub/widgets/upstream_common.dart';
import 'package:diting_desktop/widgets/desktop_picker.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class _PresetProvider {
  const _PresetProvider(this.name, this.presets);

  final String name;

  /// Protocol to `(id, server, url)`.
  final Map<String, ({String id, String server, String url})> presets;
}

const _presetProviders = [
  _PresetProvider('AliDNS', {
    'PLAIN': (id: 'AliDNS', server: '223.5.5.5:53', url: ''),
    'DOT': (id: 'AliDNS (DoT)', server: 'dns.alidns.com:853', url: ''),
    'DOH': (
      id: 'AliDNS (DoH)',
      server: 'dns.alidns.com',
      url: 'https://dns.alidns.com/dns-query',
    ),
  }),
  _PresetProvider('DNSPod', {
    'PLAIN': (id: 'DNSPod', server: '119.29.29.29:53', url: ''),
    'DOT': (id: 'DNSPod (DoT)', server: 'dot.pub:853', url: ''),
    'DOH': (
      id: 'DNSPod (DoH)',
      server: 'doh.pub',
      url: 'https://doh.pub/dns-query',
    ),
  }),
  _PresetProvider('Cloudflare', {
    'PLAIN': (id: 'Cloudflare (DNS)', server: '1.1.1.1:53', url: ''),
    'DOT': (
      id: 'Cloudflare (DoT)',
      server: '1dot1dot1dot1.cloudflare-dns.com:853',
      url: '',
    ),
    'DOH': (
      id: 'Cloudflare (DoH)',
      server: 'cloudflare-dns.com',
      url: 'https://cloudflare-dns.com/dns-query',
    ),
    'DOH3': (
      id: 'Cloudflare (DoH3)',
      server: 'cloudflare-dns.com',
      url: 'https://cloudflare-dns.com/dns-query',
    ),
  }),
  _PresetProvider('Google', {
    'PLAIN': (id: 'Google (DNS)', server: '8.8.8.8:53', url: ''),
    'DOT': (id: 'Google (DoT)', server: 'dns.google:853', url: ''),
    'DOH': (
      id: 'Google (DoH)',
      server: 'dns.google',
      url: 'https://dns.google/dns-query',
    ),
    'DOH3': (
      id: 'Google (DoH3)',
      server: 'dns.google',
      url: 'https://dns.google/dns-query',
    ),
  }),
  _PresetProvider('AdGuard', {
    'PLAIN': (id: 'AdGuard (DNS)', server: '94.140.14.14:53', url: ''),
    'DOT': (
      id: 'AdGuard (DoT)',
      server: 'dns.adguard-dns.com:853',
      url: '',
    ),
    'DOH': (
      id: 'AdGuard (DoH)',
      server: 'dns.adguard-dns.com',
      url: 'https://dns.adguard-dns.com/dns-query',
    ),
    'DOQ': (
      id: 'AdGuard (DoQ)',
      server: 'dns.adguard-dns.com:853',
      url: '',
    ),
  }),
];

/// Opens the editor. Returns the provider to save, or null when cancelled.
Future<DesktopUpstreamProvider?> showUpstreamEditor(
  BuildContext context, {
  DesktopUpstreamProvider? editing,
}) => showFloatingDialog<DesktopUpstreamProvider>(
  context: context,
  child: UpstreamEditorDialog(editing: editing),
);

class UpstreamEditorDialog extends ConsumerStatefulWidget {
  const UpstreamEditorDialog({super.key, this.editing});

  final DesktopUpstreamProvider? editing;

  @override
  ConsumerState<UpstreamEditorDialog> createState() =>
      _UpstreamEditorDialogState();
}

class _UpstreamEditorDialogState extends ConsumerState<UpstreamEditorDialog> {
  late final _id = TextEditingController(text: widget.editing?.id ?? '');
  late final _server = TextEditingController(
    text: widget.editing?.server ?? '',
  );
  late final _url = TextEditingController(text: widget.editing?.url ?? '');
  late final _pin = TextEditingController(text: widget.editing?.pin ?? '');
  final _stamp = TextEditingController();

  late String _protocol = widget.editing?.protocol ?? 'DOT';
  late bool _pinShown = widget.editing?.pin.isNotEmpty ?? false;
  String? _presetProvider;
  String? _presetNote;
  String? _stampMessage;
  String? _error;
  bool _parsingStamp = false;

  @override
  void initState() {
    super.initState();
    _pin.addListener(_onPinChanged);
  }

  void _onPinChanged() {
    final isSet = _pin.text.trim().isNotEmpty;
    if (_pinShown != isSet) setState(() => _pinShown = isSet);
  }

  @override
  void dispose() {
    _pin.removeListener(_onPinChanged);
    _id.dispose();
    _server.dispose();
    _url.dispose();
    _pin.dispose();
    _stamp.dispose();
    super.dispose();
  }

  void _applyPreset(_PresetProvider provider, String protocol) {
    final preset = provider.presets[protocol];
    setState(() {
      _protocol = protocol;
      _presetProvider = provider.name;
      _presetNote = preset == null
          ? context.l10n.desktopUpstreamPresetMissing
          : null;
      if (preset != null) {
        _id.text = preset.id;
        _server.text = preset.server;
        _url.text = preset.url;
        _pin.clear();
      }
    });
  }

  Future<void> _parseStamp() async {
    final raw = _stamp.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = context.l10n.desktopUpstreamStampEmpty);
      return;
    }
    setState(() {
      _parsingStamp = true;
      _error = null;
      _stampMessage = null;
    });
    try {
      final result = await ref
          .read(desktopApiClientProvider)
          .parseStamp(raw);
      if (!mounted) return;
      setState(() {
        _protocol = result.protocol;
        _server.text = result.server;
        _url.text = result.url;
        _pin.text = result.pin;
        if (_id.text.trim().isEmpty) {
          _id.text = result.providerName.isEmpty
              ? result.server
              : result.providerName;
        }
        _presetProvider = null;
        _presetNote = null;
        _stampMessage = context.l10n.desktopUpstreamStampParsed(
          result.protoName,
        );
      });
    } on DesktopApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = context.l10n.desktopUpstreamStampFailed(error.message),
        );
      }
    } finally {
      if (mounted) setState(() => _parsingStamp = false);
    }
  }

  void _save() {
    final l10n = context.l10n;
    final id = _id.text.trim();
    final server = _server.text.trim();
    if (id.isEmpty || server.isEmpty) {
      setState(() => _error = l10n.desktopUpstreamInvalid);
      return;
    }
    final url = _url.text.trim();
    if (desktopIsHttpsStyle(_protocol)) {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.isAbsolute || uri.scheme != 'https') {
        setState(() => _error = l10n.upstreamDohNeedsHttps);
        return;
      }
    }
    popFloatingDialog(
      context,
      DesktopUpstreamProvider(
        id: id,
        protocol: _protocol,
        server: server,
        url: url,
        weight: widget.editing?.weight ?? 1,
        pin: _pin.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: widget.editing == null
          ? l10n.desktopUpstreamAddTitle
          : l10n.desktopUpstreamEditTitle,
      hasFields: true,
      width: 460,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(onPressed: _save, child: Text(l10n.commonSave)),
      ],
      child: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              _presetBox(context),
              _stampBox(context),
              TextFormField(
                controller: _id,
                decoration: InputDecoration(
                  labelText: l10n.desktopUpstreamName,
                ),
                style: AppTextStyle.callout.of(context),
              ),
              Row(
                spacing: 12,
                children: [
                  Text(
                    l10n.desktopUpstreamProtocol,
                    style: AppTextStyle.callout.of(context),
                  ),
                  DesktopPicker(
                    glyph: AppGlyphs.layers,
                    semanticLabel: l10n.desktopUpstreamProtocol,
                    label: desktopProtocolLabel(_protocol),
                    items: [
                      for (final protocol in desktopUpstreamProtocols)
                        CommonPopupMenuItem(
                          label: desktopProtocolLabel(protocol),
                          checked: protocol == _protocol,
                          onPressed: () {
                            _PresetProvider? provider;
                            for (final item in _presetProviders) {
                              if (item.name == _presetProvider) {
                                provider = item;
                                break;
                              }
                            }
                            if (provider == null) {
                              setState(() => _protocol = protocol);
                            } else {
                              _applyPreset(provider, protocol);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
              TextFormField(
                controller: _server,
                decoration: InputDecoration(
                  labelText: l10n.desktopUpstreamAddress,
                  hintText: '223.5.5.5:53 / dns.alidns.com',
                ),
                style: AppTextStyle.callout.of(context),
              ),
              if (desktopIsHttpsStyle(_protocol))
                TextFormField(
                  controller: _url,
                  decoration: InputDecoration(
                    labelText: l10n.desktopUpstreamUrl,
                    hintText: 'https://dns.alidns.com/dns-query',
                  ),
                  style: AppTextStyle.callout.of(context),
                ),
              TextFormField(
                controller: _pin,
                decoration: InputDecoration(
                  labelText: l10n.desktopUpstreamPin,
                ),
                style: AppTextStyle.callout.of(context),
              ),
              if (_pinShown)
                Text(
                  l10n.desktopUpstreamPinWarning,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: context.colorScheme.warning),
                ),
              if (_error case final error?)
                Text(
                  error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: context.colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetBox(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            context.l10n.desktopUpstreamPreset,
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final provider in _presetProviders)
                TonalButton(
                  size: TonalButtonSize.compact,
                  label: provider.name,
                  onPressed: () => _applyPreset(provider, _protocol),
                ),
            ],
          ),
          if (_presetNote case final note?)
            Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1.of(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _stampBox(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            context.l10n.desktopUpstreamStamp,
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _stamp,
                  decoration: InputDecoration(
                    hintText: context.l10n.desktopUpstreamStampHint,
                  ),
                  style: AppTextStyle.callout.of(context),
                ),
              ),
              TonalButton(
                size: TonalButtonSize.compact,
                label: _parsingStamp
                    ? context.l10n.desktopUpstreamStampParsing
                    : context.l10n.desktopUpstreamStampParse,
                onPressed: _parsingStamp ? null : _parseStamp,
              ),
            ],
          ),
          if (_stampMessage case final message?)
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1.of(context).copyWith(
                color: colorScheme.success,
              ),
            ),
        ],
      ),
    );
  }
}
