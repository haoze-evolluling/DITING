import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_presets.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/pages/hub/provider_editor.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

Future<ServerProviderConfig?> showServerProviderPicker(
  BuildContext context, {
  required List<ServerProviderConfig> existingProviders,
}) => showSheet<ServerProviderConfig>(
  context: context,
  builder: (_) =>
      ServerProviderPickerSheet(existingProviders: existingProviders),
);

class ServerProviderPickerSheet extends ConsumerStatefulWidget {
  const ServerProviderPickerSheet({super.key, required this.existingProviders});

  final List<ServerProviderConfig> existingProviders;

  @override
  ConsumerState<ServerProviderPickerSheet> createState() =>
      _ServerProviderPickerSheetState();
}

class _ServerProviderPickerSheetState
    extends ConsumerState<ServerProviderPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DnsProviderEntry> _filtered(List<DnsProviderEntry> providers) {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return providers;
    return [
      for (final provider in providers)
        if (provider.name.toLowerCase().contains(needle) ||
            provider.address.toLowerCase().contains(needle) ||
            provider.protocol.storageValue.toLowerCase().contains(needle))
          provider,
    ];
  }

  Future<void> _addCustom() async {
    final draft = await showFloatingDialog<ProviderDraft>(
      context: context,
      child: const ProviderEditor(protocol: ProviderProtocol.dot),
    );
    if (draft == null || !mounted) return;
    final protocol = serverProtocolForUi(draft.protocol);
    Navigator.of(context).pop(
      ServerProviderConfig(
        id: draft.name,
        protocol: protocol,
        server: protocol == 'DOH' ? '' : draft.address,
        url: protocol == 'DOH' ? draft.address : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filtered(defaultDnsProviders(context.l10n));
    final groups = [
      for (final protocol in DnsProtocol.values)
        (
          protocol,
          [
            for (final provider in visible)
              if (provider.protocol == protocol) provider,
          ],
        ),
    ];
    return CommonScaffold(
      title: context.l10n.serverUpstreamAdd,
      body: ListView(
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SearchField(
              controller: _search,
              hintText: context.l10n.providerSheetSearchHint,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (visible.isEmpty)
            ListFooter(
              text: _query.trim().isEmpty
                  ? context.l10n.resolutionNoProviders
                  : UiLocalizations.of(context).noSearchResults,
            )
          else
            for (final (protocol, providers) in groups)
              if (providers.isNotEmpty)
                generateSection(
                  title: _protocolLabel(protocol),
                  items: [
                    for (final provider in providers) _presetRow(provider),
                  ],
                ),
          const ListSectionGap(),
          generateSection(
            title: context.l10n.providerMgmtCustom,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.circle_plus, size: 20),
                title: Text(context.l10n.providerMgmtAdd),
                subtitle: Text(context.l10n.providerMgmtEmptyCustomSubtitle),
                trailing: const Icon(TablerIcons.chevron_right, size: 18),
                onTap: _addCustom,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetRow(DnsProviderEntry provider) {
    final preset = serverProviderFromPreset(provider);
    final added = widget.existingProviders.any(
      (existing) =>
          existing.protocol == preset.protocol &&
          existing.address.toLowerCase() == preset.address.toLowerCase(),
    );
    return ListItem(
      leading: Icon(_protocolGlyph(provider.protocol), size: 20),
      title: Text(provider.name),
      subtitle: Text(
        '${_protocolLabel(provider.protocol)} · ${provider.address}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        added ? TablerIcons.check : TablerIcons.circle_plus,
        size: 18,
      ),
      onTap: added ? null : () => Navigator.of(context).pop(preset),
    );
  }

  String _protocolLabel(DnsProtocol protocol) => switch (protocol) {
    DnsProtocol.dns => ProviderProtocol.dns.label,
    DnsProtocol.doh => ProviderProtocol.doh.label,
    DnsProtocol.dot => ProviderProtocol.dot.label,
  };

  IconData _protocolGlyph(DnsProtocol protocol) => switch (protocol) {
    DnsProtocol.doh => TablerIcons.lock,
    DnsProtocol.dot => TablerIcons.rosette_discount_check,
    DnsProtocol.dns => TablerIcons.server_2,
  };
}
