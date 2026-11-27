import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_presets.dart';
import 'package:diting_android/pages/hub/provider_editor.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_upstream_provider_picker.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerUpstreamProvidersPage extends ConsumerWidget {
  const ServerUpstreamProvidersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverUpstreamProviders,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final providers = config.upstream.providers;
    return CommonScaffold(
      title: context.l10n.serverUpstreamProviders,
      primaryAction: IconButtonData(
        glyph: TablerIcons.plus,
        tooltip: context.l10n.serverUpstreamAdd,
        onPressed: () => _add(context, ref, config),
      ),
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverUpstreamProviders,
            items: [
              if (providers.isEmpty)
                ListItem(
                  leading: const Icon(TablerIcons.alert_triangle),
                  title: Text(context.l10n.serverUpstreamRequired),
                ),
              for (final provider in providers)
                ListItem(
                  leading: Icon(
                    _protocolGlyph(provider.protocol),
                    size: 20,
                  ),
                  title: Text(provider.id),
                  subtitle: Text(
                    [
                      serverProtocolLabel(provider.protocol),
                      provider.address,
                      if (provider.weight > 0)
                        context.l10n.serverUpstreamWeightValue(
                          provider.weight,
                        ),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: CommonPopupBox(
                    targetBuilder: (open) => IconButton(
                      tooltip: UiLocalizations.of(context).more,
                      onPressed: open,
                      icon: const Icon(TablerIcons.dots),
                    ),
                    popupBuilder: (_) => CommonPopupMenu(
                      items: [
                        CommonPopupMenuItem(
                          label: context.l10n.subsEdit,
                          glyph: TablerIcons.pencil,
                          onPressed: () =>
                              _edit(context, ref, config, provider: provider),
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.serverUpstreamWeight,
                          subtitle: '${provider.weight}',
                          glyph: TablerIcons.scale,
                          onPressed: () =>
                              _editWeight(context, ref, config, provider),
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.serverUpstreamDelete,
                          glyph: TablerIcons.trash,
                          danger: true,
                          onPressed: providers.length <= 1
                              ? null
                              : () =>
                                    _delete(context, ref, config, provider.id),
                        ),
                      ],
                    ),
                  ),
                  onTap: () => _edit(context, ref, config, provider: provider),
                ),
            ],
            footer: context.l10n.serverUpstreamProviderNote,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
  ) async {
    final next = await showServerProviderPicker(
      context,
      existingProviders: config.upstream.providers,
    );
    if (next == null || !context.mounted) return;
    final providers = [...config.upstream.providers, next];
    if (_hasDuplicate(providers)) {
      showAppSnack(context, context.l10n.serverUpstreamDuplicate);
      return;
    }
    await _write(context, ref, config, providers);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config, {
    required ServerProviderConfig provider,
  }) async {
    final initialProtocol = serverUiProtocol(provider.protocol);
    final draft = await showFloatingDialog<ProviderDraft>(
      context: context,
      child: ProviderEditor(
        protocol: initialProtocol,
        initial: MockProvider(
          id: provider.id,
          name: provider.id,
          protocol: initialProtocol,
          address: provider.address,
          latencyMs: -1,
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    final protocol = serverProtocolForUi(draft.protocol);
    final next = ServerProviderConfig(
      id: draft.name,
      protocol: protocol,
      server: protocol == 'DOH' ? '' : draft.address,
      url: protocol == 'DOH' ? draft.address : '',
    );
    final index = config.upstream.providers.indexWhere(
      (item) => item.id == provider.id,
    );
    final providers = [...config.upstream.providers];
    if (index >= 0) {
      providers[index] = next;
    } else {
      providers.add(next);
    }
    if (_hasDuplicate(providers)) {
      showAppSnack(context, context.l10n.serverUpstreamDuplicate);
      return;
    }
    await _write(context, ref, config, providers);
  }

  Future<void> _editWeight(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
    ServerProviderConfig provider,
  ) async {
    final value = await editServerNumber(
      context,
      title: context.l10n.serverUpstreamWeight,
      initial: provider.weight,
      min: 0,
      max: 100,
    );
    if (value == null || !context.mounted) return;
    final next = ServerProviderConfig(
      id: provider.id,
      protocol: provider.protocol,
      server: provider.server,
      url: provider.url,
      weight: value,
      pin: provider.pin,
    );
    await _write(context, ref, config, [
      for (final item in config.upstream.providers)
        if (item.id == provider.id) next else item,
    ]);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
    String id,
  ) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.serverUpstreamDelete,
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
        child: Text(context.l10n.serverUpstreamDeleteBody(id)),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _write(context, ref, config, [
      for (final provider in config.upstream.providers)
        if (provider.id != id) provider,
    ]);
  }

  Future<void> _write(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
    List<ServerProviderConfig> providers,
  ) async {
    try {
      await ref
          .read(serverControllerProvider.notifier)
          .saveConfig(
            config.copyWith(
              upstream: config.upstream.copyWith(providers: providers),
            ),
          );
      if (context.mounted) {
        showAppSnack(context, context.l10n.serverUpstreamSaved);
      }
    } catch (error) {
      if (context.mounted) showAppSnack(context, error.toString());
    }
  }

  bool _hasDuplicate(List<ServerProviderConfig> providers) {
    final ids = providers.map((provider) => provider.id.toLowerCase()).toSet();
    return ids.length != providers.length;
  }
}

IconData _protocolGlyph(String protocol) => switch (protocol) {
  'DOH' => TablerIcons.lock,
  'DOT' => TablerIcons.rosette_discount_check,
  _ => TablerIcons.server_2,
};
