library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_android/pages/config/config_common.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_android/ui/support/input_limits.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'user_agents_dialog.dart';

String _agentKindLabel(MockUserAgent? agent, AppL10n l10n) {
  if (agent == null) return l10n.uaNoOverrideBody;
  return agent.isDefault ? l10n.uaBuiltin : l10n.uaCustom;
}

class UserAgentsConfigPage extends ConsumerWidget {
  const UserAgentsConfigPage({super.key});

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MockUserAgent agent,
  ) async {
    final confirmed = await confirmConfigAction(
      context,
      title: context.l10n.uaDeleteTitle,
      message: context.l10n.uaDeleteBody,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    ref.read(configResourcesProvider.notifier).removeUserAgent(agent.value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = ref.watch(configResourcesProvider);
    final agents = resources.userAgents;
    final selected = resources.selectedUserAgent;
    final notifier = ref.read(configResourcesProvider.notifier);
    MockUserAgent? selectedAgent;
    for (final agent in agents) {
      if (agent.value == selected) {
        selectedAgent = agent;
        break;
      }
    }
    return CommonScaffold(
      title: context.l10n.customResourcesTitle,
      iconActions: [
        IconButtonData(
          glyph: TablerIcons.plus,
          tooltip: context.l10n.uaAdd,
          onPressed: () => showUserAgentDialog(context, ref),
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.uaCurrent,
            items: [
              ListItem(
                leading: Icon(
                  selectedAgent == null
                      ? TablerIcons.user
                      : TablerIcons.circle_check,
                ),
                title: Text(
                  selectedAgent?.displayName ?? context.l10n.uaNoOverride,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_agentKindLabel(selectedAgent, context.l10n)),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.uaAll,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.circle_check),
                title: Text(context.l10n.uaNoOverride),
                subtitle: Text(context.l10n.uaNoOverrideBody),
                trailing: selected == null ? const SelectionCheck() : null,
                onTap: () => notifier.selectUserAgent(null),
              ),
              for (final agent in agents)
                ListItem(
                  leading: const Icon(TablerIcons.user),
                  title: Text(
                    agent.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    agent.isDefault
                        ? context.l10n.uaBuiltin
                        : context.l10n.uaCustom,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      if (agent.value == selected) const SelectionCheck(),
                      if (!agent.isDefault) ...[
                        ConfigRemoveButton(
                          tooltip: context.l10n.uaEdit,
                          glyph: TablerIcons.pencil,
                          onPressed: () => showUserAgentDialog(
                            context,
                            ref,
                            existing: agent,
                          ),
                        ),
                        ConfigRemoveButton(
                          tooltip: context.l10n.configDelete,
                          onPressed: () => _delete(context, ref, agent),
                        ),
                      ],
                    ],
                  ),
                  onTap: () => notifier.selectUserAgent(agent.value),
                ),
            ],
            footer: context.l10n.uaBuiltinNote,
          ),
        ],
      ),
    );
  }
}
