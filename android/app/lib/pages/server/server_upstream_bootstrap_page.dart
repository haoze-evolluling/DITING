import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_presets.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/pages/hub/bootstrap_entry_editor.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerUpstreamBootstrapPage extends ConsumerWidget {
  const ServerUpstreamBootstrapPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverBootstrapSummary,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final upstream = config.upstream;
    final presets = defaultBootstrapEntries(context.l10n);
    final presetIds = {for (final preset in presets) preset.id};
    final selected = {for (final entry in upstream.bootstrap) entry.id};
    final custom = [
      for (final entry in upstream.bootstrap)
        if (!presetIds.contains(entry.id)) entry,
    ];
    return CommonScaffold(
      title: context.l10n.serverBootstrapSummary,
      primaryAction: IconButtonData(
        glyph: AppGlyphs.add,
        tooltip: context.l10n.bootstrapAdd,
        onPressed: () => _addCustom(context, ref, config),
      ),
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.bootstrapGlobal,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.language, size: 20),
                title: Text(context.l10n.bootstrapEnable),
                subtitle: Text(context.l10n.bootstrapEnableBody),
                value: upstream.bootstrapEnabled,
                onChanged: (value) => _save(
                  context,
                  ref,
                  config.copyWith(
                    upstream: upstream.copyWith(bootstrapEnabled: value),
                  ),
                ),
              ),
            ],
            footer: context.l10n.bootstrapEnableNote,
          ),
          generateSection(
            title: context.l10n.bootstrapBuiltin,
            items: [
              for (final preset in presets)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.dns, size: 20),
                  title: Text(preset.name),
                  subtitle: Text(preset.ip),
                  trailing: CommonCheckBox(
                    value: selected.contains(preset.id),
                    onChanged: upstream.bootstrapEnabled
                        ? (value) => _togglePreset(
                            context,
                            ref,
                            config,
                            presets: presets,
                            selected: selected,
                            preset: preset,
                            enabled: value ?? true,
                          )
                        : null,
                  ),
                  onTap: upstream.bootstrapEnabled
                      ? () => _togglePreset(
                          context,
                          ref,
                          config,
                          presets: presets,
                          selected: selected,
                          preset: preset,
                          enabled: !selected.contains(preset.id),
                        )
                      : null,
                ),
            ],
          ),
          generateSection(
            title: context.l10n.bootstrapCustom,
            items: [
              if (custom.isEmpty)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.info, size: 20),
                  title: Text(context.l10n.bootstrapNoCustom),
                ),
              for (final entry in custom)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.upstream, size: 20),
                  title: Text(entry.name.isEmpty ? entry.id : entry.name),
                  subtitle: Text(entry.address),
                  trailing: IconButton(
                    tooltip: context.l10n.appRulesDelete,
                    onPressed: upstream.bootstrapEnabled
                        ? () => _deleteCustom(context, ref, config, entry)
                        : null,
                    icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                  ),
                ),
            ],
          ),
          ListFooter(
            text: upstream.bootstrap.isEmpty
                ? context.l10n.serverBootstrapDefault
                : context.l10n.serverBootstrapNote,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _togglePreset(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config, {
    required List<BootstrapEntry> presets,
    required Set<String> selected,
    required BootstrapEntry preset,
    required bool enabled,
  }) async {
    final next = {...selected};
    if (enabled) {
      next.add(preset.id);
    } else {
      next.remove(preset.id);
    }
    final presetIds = {for (final item in presets) item.id};
    final custom = [
      for (final entry in config.upstream.bootstrap)
        if (!presetIds.contains(entry.id)) entry,
    ];
    await _write(context, ref, config, [
      for (final item in presets)
        if (next.contains(item.id)) serverBootstrapFromPreset(item),
      ...custom,
    ]);
  }

  Future<void> _addCustom(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
  ) async {
    final draft = await showFloatingDialog<BootstrapEntryDraft>(
      context: context,
      child: const BootstrapEntryEditor(),
    );
    if (draft == null || !context.mounted) return;
    await _write(context, ref, config, [
      ...config.upstream.bootstrap,
      ServerBootstrapConfig(
        id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
        name: draft.name.isEmpty ? draft.ip : draft.name,
        address: draft.ip,
      ),
    ]);
  }

  Future<void> _deleteCustom(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
    ServerBootstrapConfig target,
  ) async {
    await _write(context, ref, config, [
      for (final entry in config.upstream.bootstrap)
        if (entry.id != target.id) entry,
    ]);
  }

  Future<void> _write(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
    List<ServerBootstrapConfig> bootstrap,
  ) async {
    await _save(
      context,
      ref,
      config.copyWith(upstream: config.upstream.copyWith(bootstrap: bootstrap)),
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
