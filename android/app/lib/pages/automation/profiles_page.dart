/// Configuration profiles (A3): one-tap snapshots of work mode / upstream set / rule groups / toggles.
///
/// A profile is an `automation_profile` row whose `payload.kind` is `config`. Applying one is an
/// audited event here (the actual engine switch is the `switch_profile` automation action); the
/// page owns create / rename / delete so a scene can bind to a stable id.
library;

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/state/automation_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ProfilesPage extends ConsumerWidget {
  const ProfilesPage({super.key});

  static const _modes = ['normal', 'express', 'server'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(automationProfilesProvider);
    return CommonScaffold(
      title: context.l10n.profilesTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.profilesAdd,
          onPressed: () => _create(context, ref),
          icon: const GlyphIcon(AppGlyphs.add),
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.profilesIntro),
          profiles.when(
            data: (list) {
              final configs = [
                for (final profile in list)
                  if ((profile.payload['kind'] as String?) != 'network') profile,
              ];
              if (configs.isEmpty) {
                return PageIntroCard(text: context.l10n.profilesEmpty);
              }
              return generateSection(
                title: context.l10n.profilesListSection,
                items: [
                  for (final profile in configs)
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.profiles),
                      title: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${profile.workMode} · ${profile.upstreamSet.isEmpty ? '—' : profile.upstreamSet}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _apply(context, ref, profile),
                            child: Text(context.l10n.profilesApply),
                          ),
                          IconButton(
                            tooltip: context.l10n.profilesDelete,
                            onPressed: () => ref
                                .read(automationControllerProvider)
                                .deleteProfile(profile.id),
                            icon: const GlyphIcon(AppGlyphs.remove),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, _) => PageIntroCard(text: '$error'),
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final upstream = TextEditingController();
    var mode = _modes.first;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(context.l10n.profilesAdd),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: context.l10n.profilesName),
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: mode,
                isExpanded: true,
                onChanged: (value) => setState(() => mode = value ?? mode),
                items: [
                  for (final item in _modes)
                    DropdownMenuItem(value: item, child: Text(item)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: upstream,
                decoration: InputDecoration(
                  labelText: context.l10n.profilesUpstreamSet,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.profilesCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.profilesSave),
            ),
          ],
        ),
      ),
    );
    if (created != true || !context.mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref
        .read(automationControllerProvider)
        .saveProfile(
          AutomationProfile(
            id: newAutomationId('profile'),
            name: name.text.trim().isEmpty ? 'profile' : name.text.trim(),
            payload: {
              'kind': 'config',
              'workMode': mode,
              'upstreamSet': upstream.text.trim(),
              'ruleGroupStates': const <String>[],
              'featureToggles': const <String, Object?>{},
            },
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    AutomationProfile profile,
  ) async {
    await ref
        .read(automationControllerProvider)
        .logEvent(
          AutomationEvent(
            ts: DateTime.now().millisecondsSinceEpoch,
            event: 'profile.applied',
            outcome: 'ok',
            detail: {'profileId': profile.id, 'name': profile.name},
          ),
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.profilesApplied(profile.name))),
      );
    }
  }
}
