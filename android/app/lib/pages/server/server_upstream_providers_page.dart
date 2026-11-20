import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_presets.dart';
import 'package:diting_android/pages/hub/provider_editor.dart';
import 'package:diting_android/pages/server/server_upstream_provider_picker.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
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
        glyph: AppGlyphs.add,
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
                  leading: const GlyphIcon(AppGlyphs.warning),
                  title: Text(context.l10n.serverUpstreamRequired),
                ),
              for (final provider in providers)
                ListItem(
                  leading: GlyphIcon(
                    _protocolGlyph(provider.protocol),
                    size: 20,
                  ),
                  title: Text(provider.id),
                  subtitle: Text(
                    '${serverProtocolLabel(provider.protocol)} · '
                    '${provider.address}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: context.l10n.serverUpstreamDelete,
                    onPressed: providers.length <= 1
                        ? null
                        : () => _delete(context, ref, config, provider.id),
                    icon: const GlyphIcon(AppGlyphs.delete, size: 18),
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

Glyph _protocolGlyph(String protocol) => switch (protocol) {
  'DOH' || 'DOH3' => AppGlyphs.lock,
  'DOT' => AppGlyphs.verified,
  _ => AppGlyphs.dns,
};
