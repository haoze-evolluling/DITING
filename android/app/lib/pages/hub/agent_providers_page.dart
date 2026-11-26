// ignore_for_file: sort_child_properties_last
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/pages/hub/agent_provider_editor.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
          glyph: TablerIcons.plus,
          tooltip: context.l10n.agentProvidersAdd,
          onPressed: () => _edit(context, ref),
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.agentProvidersMine,
            items: [
              if (state.providers.isEmpty)
                ListItem(
                  title: Text(context.l10n.agentProvidersEmpty),
                  subtitle: Text(context.l10n.agentProvidersEmptySubtitle),
                  leading: Icon(TablerIcons.info_circle),
                ),
              for (final provider in state.providers)
                _providerRow(
                  context,
                  ref,
                  notifier,
                  provider,
                  active: provider.id == state.activeProviderId,
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
                  _presetRow(
                    context,
                    ref,
                    preset,
                    added: added.contains(preset.id),
                  ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _providerRow(
    BuildContext context,
    WidgetRef ref,
    AgentApiNotifier notifier,
    AiProviderConfig provider, {
    required bool active,
  }) {
    return ListItem(
      leading: Icon(
        active ? TablerIcons.circle_check : TablerIcons.devices,
        size: 20,
        color: active ? context.colorScheme.primary : null,
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
            onPressed: () => _edit(context, ref, existing: provider),
            icon: const Icon(TablerIcons.pencil, size: 20),
          ),
          IconButton(
            tooltip: context.l10n.commonDelete,
            onPressed: () => _delete(context, notifier, provider),
            icon: const Icon(TablerIcons.trash, size: 20),
          ),
        ],
      ),
      onTap: () => notifier.selectProvider(provider.id),
    );
  }

  Widget _presetRow(
    BuildContext context,
    WidgetRef ref,
    AiProviderPreset preset, {
    required bool added,
  }) {
    final colorScheme = context.colorScheme;
    return ListItem(
      leading: Icon(
        added ? TablerIcons.circle_check : TablerIcons.circle_plus,
        size: 20,
      ),
      title: Text(preset.name),
      subtitle: Text(preset.baseUrl),
      trailing: TonalChip(
        label: added ? context.l10n.agentProvidersAdded : context.l10n.formAdd,
        color: added
            ? context.raisedSurfaceLevel.colorOf(colorScheme)
            : colorScheme.primary,
        foregroundColor: added
            ? colorScheme.onSurfaceVariant
            : colorScheme.onPrimary,
        onPressed: added ? null : () => _edit(context, ref, preset: preset),
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
    final id = existing?.id ?? _newProviderId(preset);
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

  static String _newProviderId(AiProviderPreset? preset) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (preset == null) return 'provider_$stamp';
    return 'preset_${preset.id}_$stamp';
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
        child: Text(context.l10n.agentProvidersDeleteBody(provider.name)),
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
