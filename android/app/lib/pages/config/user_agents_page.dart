/// User-Agent page (upstream `views/config/user_agents.dart`).
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_android/pages/config/config_common.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_shared/ui/support/input_limits.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/note_card.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'user_agents_dialog.dart';

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
    return CommonScaffold(
      title: 'User-Agent',
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.uaAdd,
          onPressed: () => showUserAgentDialog(context, ref),
        ),
      ],
      body: PageBody(
        children: [
          NoteCard(
            text:
                context.l10n.uaNote,
            glyph: AppGlyphs.account,
          ),
          generateSection(
            title: context.l10n.uaCurrent,
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
                    agent.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(agent.isDefault ? context.l10n.uaBuiltin : context.l10n.uaCustom),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      if (agent.value == selected) const SelectionCheck(),
                      if (!agent.isDefault)
                        ConfigRemoveButton(
                          tooltip: context.l10n.uaEdit,
                          glyph: AppGlyphs.edit,
                          onPressed: () => showUserAgentDialog(
                            context,
                            ref,
                            existing: agent.value,
                          ),
                        ),
                      if (!agent.isDefault)
                        ConfigRemoveButton(
                          tooltip: context.l10n.configDelete,
                          onPressed: () => _delete(context, ref, agent),
                        ),
                    ],
                  ),
                  onTap: () => notifier.selectUserAgent(agent.value),
                ),
            ],
            footer:
                context.l10n.uaBuiltinNote,
          ),
        ],
      ),
    );
  }
}
