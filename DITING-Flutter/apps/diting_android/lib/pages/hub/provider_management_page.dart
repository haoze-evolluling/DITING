// ignore_for_file: sort_child_properties_last
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Provider management (upstream `ProviderManagementScreen`): current provider summary,
/// protocol switcher, built-in and custom providers. Built-in entries are selectable only.
class ProviderManagementPage extends ConsumerStatefulWidget {
  const ProviderManagementPage({super.key});

  @override
  ConsumerState<ProviderManagementPage> createState() =>
      _ProviderManagementPageState();
}

class _ProviderManagementPageState
    extends ConsumerState<ProviderManagementPage> {
  ProviderProtocol _protocol = ProviderProtocol.doh;

  List<MockProvider> get _all => ref.watch(dnsProviderCatalogProvider);

  MockProvider? get _selected {
    final selectedId = ref.watch(selectedProviderProvider);
    return _all.where((provider) => provider.id == selectedId).firstOrNull;
  }

  void _select(MockProvider provider) {
    ref.read(selectedProviderProvider.notifier).select(provider.id);
    setState(() {});
  }

  Future<void> _add() async {
    final draft = await showFloatingDialog<_ProviderDraft>(
      context: context,
      child: _ProviderEditor(protocol: _protocol),
    );
    if (draft == null || !mounted) {
      return;
    }
    final notifier = ref.read(dnsProviderCatalogProvider.notifier);
    notifier.addCustom(
      name: draft.name,
      protocol: draft.protocol,
      address: draft.address,
    );
    final created = ref.read(dnsProviderCatalogProvider).last;
    ref.read(selectedProviderProvider.notifier).select(created.id);
    setState(() => _protocol = draft.protocol);
  }

  Future<void> _edit(MockProvider provider) async {
    final draft = await showFloatingDialog<_ProviderDraft>(
      context: context,
      child: _ProviderEditor(protocol: provider.protocol, initial: provider),
    );
    if (draft == null || !mounted) {
      return;
    }
    ref
        .read(dnsProviderCatalogProvider.notifier)
        .updateCustom(
          id: provider.id,
          name: draft.name,
          protocol: draft.protocol,
          address: draft.address,
        );
    setState(() => _protocol = draft.protocol);
  }

  Future<void> _delete(MockProvider provider) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.providerMgmtDeleteTitle,
        destructive: true,
        child: Text(context.l10n.providerMgmtDeleteBody(provider.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    ref.read(dnsProviderCatalogProvider.notifier).deleteCustom(provider.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final list = _all
        .where((provider) => provider.protocol == _protocol)
        .toList(growable: false);
    final presets = list.where((provider) => provider.isPreset).toList();
    final customs = list.where((provider) => !provider.isPreset).toList();
    final selected = _selected;
    final selectedId = ref.watch(selectedProviderProvider);
    return CommonScaffold(
      title: context.l10n.providerMgmtTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.providerMgmtAdd,
          onPressed: _add,
        ),
      ],
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                spacing: 12,
                children: [
                  GlyphIcon(
                    AppGlyphs.dns,
                    size: 22,
                    color: colorScheme.primary,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(context.l10n.providerMgmtCurrent, style: context.listTitleStyle),
                        Text(
                          selected == null
                              ? context.l10n.resolutionNotConfigured
                              : '(${selected.protocol.label}) ${selected.name}',
                          style: context.listSubtitleStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: SegmentedControl<ProviderProtocol>(
              segments: [
                for (final protocol in ProviderProtocol.values)
                  (protocol, protocol.label),
              ],
              value: _protocol,
              onChanged: (value) => setState(() => _protocol = value),
            ),
          ),
          if (presets.isNotEmpty)
            generateSection(
              title: context.l10n.providerMgmtBuiltin,
              items: [
                for (final provider in presets)
                  _ProviderRow(
                    provider: provider,
                    selected: provider.id == selectedId,
                    onTap: () => _select(provider),
                  ),
              ],
            ),
          if (customs.isNotEmpty)
            generateSection(
              title: context.l10n.providerMgmtCustom,
              items: [
                for (final provider in customs)
                  _ProviderRow(
                    provider: provider,
                    selected: provider.id == selectedId,
                    onTap: () => _select(provider),
                    onEdit: () => _edit(provider),
                    onDelete: () => _delete(provider),
                  ),
              ],
            )
          else
            generateSection(
              title: context.l10n.providerMgmtCustom,
              items: [
                ListItem(
                  title: Text(context.l10n.providerMgmtEmptyCustom),
                  subtitle: Text(context.l10n.providerMgmtEmptyCustomSubtitle),
                  leading: GlyphIcon(AppGlyphs.addCircle),
                ),
              ],
            ),
          ListFooter(text: context.l10n.providerMgmtFooter),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.selected,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final MockProvider provider;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: GlyphIcon(
        provider.protocol == ProviderProtocol.doh
            ? AppGlyphs.lock
            : AppGlyphs.dns,
        size: 20,
      ),
      title: Text(provider.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        provider.address,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) const SelectionCheck(),
          if (onEdit != null)
            IconButton(
              tooltip: context.l10n.commonEdit,
              onPressed: onEdit,
              icon: const GlyphIcon(AppGlyphs.edit, size: 20),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: context.l10n.commonDelete,
              onPressed: onDelete,
              icon: const GlyphIcon(AppGlyphs.delete, size: 20),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ProviderDraft {
  const _ProviderDraft({
    required this.name,
    required this.protocol,
    required this.address,
  });

  final String name;
  final ProviderProtocol protocol;
  final String address;
}

class _ProviderEditor extends StatefulWidget {
  const _ProviderEditor({required this.protocol, this.initial});

  final ProviderProtocol protocol;
  final MockProvider? initial;

  @override
  State<_ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<_ProviderEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.initial?.address ?? '',
  );
  late ProviderProtocol _protocol = widget.protocol;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final address = _address.text.trim();
    final valid = switch (_protocol) {
      ProviderProtocol.doh => address.startsWith('https://'),
      _ => address.contains(':') && !address.contains('://'),
    };
    if (name.isEmpty) {
      setState(() => _error = context.l10n.providerMgmtNameRequired);
      return;
    }
    if (!valid) {
      setState(() {
        _error = _protocol == ProviderProtocol.doh
            ? context.l10n.providerMgmtDohRequired
            : context.l10n.providerMgmtHostPortRequired;
      });
      return;
    }
    Navigator.of(context)
        .pop(_ProviderDraft(name: name, protocol: _protocol, address: address));
  }

  @override
  Widget build(BuildContext context) {
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
              _protocol = value;
              _error = null;
            }),
          ),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: context.l10n.serverName),
          ),
          TextField(
            controller: _address,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: _protocol == ProviderProtocol.doh
                  ? context.l10n.serverDohAddress
                  : context.l10n.providerMgmtAddressLabel,
              hintText: _protocol == ProviderProtocol.doh
                  ? 'https://dns.example.com/dns-query'
                  : '1.1.1.1:853',
            ),
          ),
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
