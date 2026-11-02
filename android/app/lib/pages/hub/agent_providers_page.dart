// ignore_for_file: sort_child_properties_last
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/hub/agent_provider_editor.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// AI provider management (upstream `AiProviderManageScreen`), persisted by `AgentApiNotifier` so
/// "test connection" reflects what is on disk. An empty key keeps the existing one.
class AgentProvidersPage extends ConsumerWidget {
  const AgentProvidersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentApiProvider);
    final notifier = ref.read(agentApiProvider.notifier);
    final groups = <String, List<AiProviderPreset>>{};
    for (final preset in aiProviderPresets(context.l10n)) {
      groups.putIfAbsent(preset.group, () => []).add(preset);
    }
    final added = state.providers.map((provider) => provider.presetId).toSet();
    return CommonScaffold(
      title: context.l10n.agentProvidersTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.agentProvidersAdd,
          onPressed: () => _edit(context, ref),
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.agentProvidersIntro),
          generateSection(
            title: context.l10n.agentProvidersMine,
            items: [
              if (state.providers.isEmpty)
                ListItem(
                  title: Text(context.l10n.agentProvidersEmpty),
                  subtitle: Text(context.l10n.agentProvidersEmptySubtitle),
                  leading: GlyphIcon(AppGlyphs.info),
                ),
              for (final provider in state.providers)
                ListItem(
                  leading: GlyphIcon(
                    provider.id == state.activeProviderId
                        ? AppGlyphs.checkCircle
                        : AppGlyphs.devices,
                    size: 20,
                    color: provider.id == state.activeProviderId
                        ? context.colorScheme.primary
                        : null,
                  ),
                  title: Text(provider.name),
                  subtitle: Text(
                    context.l10n.agentProvidersRow(
                      provider.model.isEmpty
                          ? context.l10n.agentApiNoModel
                          : provider.model,
                      provider.baseUrl,
                      provider.hasKey
                          ? context.l10n.agentApiKeyConfigured
                          : context.l10n.agentProvidersKeyMissing,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: context.l10n.commonEdit,
                        onPressed: () =>
                            _edit(context, ref, existing: provider),
                        icon: const GlyphIcon(AppGlyphs.edit, size: 20),
                      ),
                      IconButton(
                        tooltip: context.l10n.commonDelete,
                        onPressed: () => _delete(context, notifier, provider),
                        icon: const GlyphIcon(AppGlyphs.delete, size: 20),
                      ),
                    ],
                  ),
                  onTap: () => notifier.selectProvider(provider.id),
                ),
            ],
            footer: state.providers.isEmpty
                ? null
                : context.l10n.agentProvidersFooter,
          ),
          for (final entry in groups.entries)
            generateSection(
              title: entry.key,
              items: [
                for (final preset in entry.value)
                  ListItem(
                    leading: GlyphIcon(
                      added.contains(preset.id)
                          ? AppGlyphs.checkCircle
                          : AppGlyphs.addCircle,
                      size: 20,
                    ),
                    title: Text(preset.name),
                    subtitle: Text(preset.baseUrl),
                    trailing: TonalChip(
                      label: added.contains(preset.id) ? context.l10n.agentProvidersAdded : context.l10n.formAdd,
                      color: added.contains(preset.id)
                          ? context.raisedSurfaceLevel.colorOf(
                              context.colorScheme,
                            )
                          : context.colorScheme.primary,
                      foregroundColor: added.contains(preset.id)
                          ? context.colorScheme.onSurfaceVariant
                          : context.colorScheme.onPrimary,
                      onPressed: added.contains(preset.id)
                          ? null
                          : () => _edit(context, ref, preset: preset),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    AiProviderConfig? existing,
    AiProviderPreset? preset,
  }) async {
    final result = await showFloatingDialog<ProviderFormResult>(
      context: context,
      child: AgentProviderEditor(existing: existing, preset: preset),
    );
    if (result == null) return;
    final notifier = ref.read(agentApiProvider.notifier);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final id =
        existing?.id ??
        (preset != null ? 'preset_${preset.id}_$stamp' : 'provider_$stamp');
    notifier.saveProvider(
      AiProviderConfig(
        id: id,
        name: result.name,
        baseUrl: result.baseUrl,
        model: result.model,
        presetId: preset?.id ?? existing?.presetId ?? '',
        sealedKey: existing?.sealedKey ?? '',
      ),
      plainKey: result.key,
    );
  }

  Future<void> _delete(
    BuildContext context,
    AgentApiNotifier notifier,
    AiProviderConfig provider,
  ) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.agentProvidersDeleteTitle,
        destructive: true,
        child: Text(
          context.l10n.agentProvidersDeleteBody(provider.name),
        ),
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
    if (confirmed == true) notifier.deleteProvider(provider.id);
  }
}
