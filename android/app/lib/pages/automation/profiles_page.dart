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
    final result = await showFloatingDialog<
      ({String name, String upstream, String mode})
    >(context: context, child: const _ProfileDialog());
    if (result == null || !context.mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref
        .read(automationControllerProvider)
        .saveProfile(
          AutomationProfile(
            id: newAutomationId('profile'),
            name: result.name.isEmpty ? 'profile' : result.name,
            payload: {
              'kind': 'config',
              'workMode': result.mode,
              'upstreamSet': result.upstream,
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

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog();

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _name = TextEditingController();
  final _upstream = TextEditingController();
  String _mode = ProfilesPage._modes.first;

  @override
  void dispose() {
    _name.dispose();
    _upstream.dispose();
    super.dispose();
  }

  static String _modeLabel(BuildContext context, String mode) => switch (mode) {
    'normal' => context.l10n.workModeNormalTitle,
    'express' => context.l10n.workModeExpressTitle,
    'server' || 'dns' => context.l10n.workModeServerTitle,
    _ => mode,
  };

  void _submit() {
    Navigator.of(context).pop((
      name: _name.text.trim(),
      upstream: _upstream.text.trim(),
      mode: _mode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.profilesAdd,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.profilesCancel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(context.l10n.profilesSave),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: context.l10n.profilesName),
          ),
          SegmentedControl<String>(
            segments: [
              for (final mode in ProfilesPage._modes)
                (mode, _modeLabel(context, mode)),
            ],
            value: _mode,
            onChanged: (value) => setState(() => _mode = value),
          ),
          TextField(
            controller: _upstream,
            decoration: InputDecoration(
              labelText: context.l10n.profilesUpstreamSet,
            ),
          ),
        ],
      ),
    );
  }
}
