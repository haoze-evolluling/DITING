import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/hub/provider_editor.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerUpstreamPage extends ConsumerWidget {
  const ServerUpstreamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverUpstreamTitle,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final upstream = config.upstream;
    return CommonScaffold(
      title: context.l10n.serverUpstreamTitle,
      primaryAction: IconButtonData(
        glyph: AppGlyphs.add,
        tooltip: context.l10n.serverUpstreamAdd,
        onPressed: () => _editProvider(context, ref, config),
      ),
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverUpstreamMode,
            items: [
              for (final mode in const [
                'primary_backup',
                'single',
                'parallel_race',
                'smart_prediction',
              ])
                ListItem(
                  leading: GlyphIcon(
                    upstream.mode == mode
                        ? AppGlyphs.checkCircle
                        : _modeGlyph(mode),
                    size: 20,
                  ),
                  title: Text(_modeLabel(context, mode)),
                  subtitle: Text(_modeDescription(context, mode)),
                  trailing: upstream.mode == mode
                      ? const SelectionCheck()
                      : null,
                  onTap: () => _save(
                    context,
                    ref,
                    config.copyWith(
                      upstream: upstream.copyWith(mode: mode),
                    ),
                  ),
                ),
            ],
            footer: context.l10n.serverUpstreamModeNote,
          ),
          generateSection(
            title: context.l10n.serverUpstreamProviders,
            items: [
              if (upstream.providers.isEmpty)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.warning),
                  title: Text(context.l10n.serverUpstreamRequired),
                ),
              for (final provider in upstream.providers)
                ListItem(
                  leading: GlyphIcon(_protocolGlyph(provider.protocol), size: 20),
                  title: Text(provider.id),
                  subtitle: Text('${provider.protocol} · ${provider.address}'),
                  trailing: IconButton(
                    tooltip: context.l10n.serverUpstreamDelete,
                    onPressed: upstream.providers.length <= 1
                        ? null
                        : () => _deleteProvider(
                            context,
                            ref,
                            config,
                            provider.id,
                          ),
                    icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                  ),
                  onTap: () => _editProvider(
                    context,
                    ref,
                    config,
                    provider: provider,
                  ),
                ),
            ],
            footer: context.l10n.serverUpstreamProviderNote,
          ),
          generateSection(
            title: context.l10n.serverUpstreamBootstrap,
            items: [
              for (final server in upstream.bootstrap)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.dns, size: 20),
                  title: Text(server.name.isEmpty ? server.id : server.name),
                  subtitle: Text(server.address),
                ),
              if (upstream.bootstrap.isEmpty)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.info, size: 20),
                  title: Text(context.l10n.serverBootstrapDefault),
                ),
            ],
            footer: context.l10n.serverBootstrapNote,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _editProvider(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config, {
    ServerProviderConfig? provider,
  }) async {
    final initialProtocol = _protocolOf(provider?.protocol ?? 'DOT');
    final draft = await showFloatingDialog<ProviderDraft>(
      context: context,
      child: ProviderEditor(
        protocol: initialProtocol,
        initial: provider == null
            ? null
            : MockProvider(
                id: provider.id,
                name: provider.id,
                protocol: initialProtocol,
                address: provider.address,
                latencyMs: -1,
              ),
      ),
    );
    if (draft == null || !context.mounted) return;
    final protocol = draft.protocol.name.toUpperCase();
    final next = ServerProviderConfig(
      id: draft.name,
      protocol: protocol,
      server: protocol == 'DOH' ? '' : draft.address,
      url: protocol == 'DOH' ? draft.address : '',
    );
    final providers = [
      for (final item in config.upstream.providers)
        if (provider == null || item.id != provider.id) item,
      next,
    ];
    final duplicate = providers.map((item) => item.id).toSet().length !=
        providers.length;
    if (duplicate) {
      if (context.mounted) {
        showAppSnack(context, context.l10n.serverUpstreamDuplicate);
      }
      return;
    }
    await _save(
      context,
      ref,
      config.copyWith(upstream: config.upstream.copyWith(providers: providers)),
    );
  }

  Future<void> _deleteProvider(
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
    await _save(
      context,
      ref,
      config.copyWith(
        upstream: config.upstream.copyWith(
          providers: [
            for (final provider in config.upstream.providers)
              if (provider.id != id) provider,
          ],
        ),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
  ) async {
    try {
      await ref.read(serverControllerProvider.notifier).saveConfig(config);
      if (context.mounted) {
        showAppSnack(context, context.l10n.serverUpstreamSaved);
      }
    } catch (error) {
      if (context.mounted) showAppSnack(context, error.toString());
    }
  }
}

ProviderProtocol _protocolOf(String protocol) => switch (protocol) {
  'DOH' || 'DOH3' => ProviderProtocol.doh,
  'DOT' => ProviderProtocol.dot,
  _ => ProviderProtocol.dns,
};

Glyph _protocolGlyph(String protocol) => switch (protocol) {
  'DOH' || 'DOH3' => AppGlyphs.lock,
  'DOT' => AppGlyphs.verified,
  _ => AppGlyphs.dns,
};

Glyph _modeGlyph(String mode) => switch (mode) {
  'single' => AppGlyphs.upstream,
  'parallel_race' => AppGlyphs.speed,
  'smart_prediction' => AppGlyphs.sparkle,
  _ => AppGlyphs.swap,
};

String _modeLabel(BuildContext context, String mode) => switch (mode) {
  'single' => context.l10n.serverModeSingle,
  'parallel_race' => context.l10n.serverModeParallel,
  'smart_prediction' => context.l10n.serverModeSmart,
  _ => context.l10n.serverModePrimaryBackup,
};

String _modeDescription(BuildContext context, String mode) => switch (mode) {
  'single' => context.l10n.serverModeSingleDesc,
  'parallel_race' => context.l10n.serverModeParallelDesc,
  'smart_prediction' => context.l10n.serverModeSmartDesc,
  _ => context.l10n.serverModePrimaryBackupDesc,
};
