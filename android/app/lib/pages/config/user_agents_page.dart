/// User-Agent management (upstream `views/config/user_agents.dart`), reached directly from the
/// feature hub after the former 自定义资源 wrapper was removed.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_android/pages/config/config_common.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_shared/ui/support/input_limits.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'user_agents_dialog.dart';

/// How the summary names the selected entry: builtin, custom, or no override at all.
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
    // The selected row is looked up once so the summary and the list agree on the label.
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
          glyph: AppGlyphs.add,
          tooltip: context.l10n.uaAdd,
          onPressed: () => showUserAgentDialog(context, ref),
        ),
      ],
      body: PageBody(
        children: [
          // A read-only summary first: it answers "what is being sent right now" without the user
          // having to scan the whole candidate list for the selected row.
          generateSection(
            title: context.l10n.uaCurrent,
            items: [
              ListItem(
                leading: GlyphIcon(
                  selectedAgent == null
                      ? AppGlyphs.account
                      : AppGlyphs.checkCircle,
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
                leading: const GlyphIcon(AppGlyphs.checkCircle),
                title: Text(context.l10n.uaNoOverride),
                subtitle: Text(context.l10n.uaNoOverrideBody),
                trailing: selected == null ? const SelectionCheck() : null,
                onTap: () => notifier.selectUserAgent(null),
              ),
              for (final agent in agents)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.account),
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
                          glyph: AppGlyphs.edit,
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
