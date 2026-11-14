/// Network profiles (N1): show the live network context, the profile it resolves to, and the
/// configurable profiles. Wi-Fi / cellular / roaming / metered can each carry a different upstream
/// set, rule-group state and toggle set; the switch happens as the context changes.
library;

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/state/automation_providers.dart';
import 'package:diting_android/state/net_profile_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class NetProfilePage extends ConsumerWidget {
  const NetProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contextAsync = ref.watch(networkContextProvider);
    final resolved = ref.watch(networkProfileResolutionProvider);
    final profiles = ref.watch(networkProfilesProvider);
    return CommonScaffold(
      title: context.l10n.netProfileTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.netProfileAdd,
          onPressed: () => _create(context, ref),
          icon: const GlyphIcon(AppGlyphs.add),
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.netProfileIntro),
          contextAsync.when(
            data: (network) => generateSection(
              title: context.l10n.netProfileCurrentNet,
              items: [
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.connections),
                  title: Text('${network['type'] ?? 'unknown'}'),
                  subtitle: Text(_contextDetail(network)),
                ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, _) => PageIntroCard(text: '$error'),
          ),
          resolved.when(
            data: (answer) => generateSection(
              title: context.l10n.netProfileResolved,
              items: [
                ListItem(
                  leading: GlyphIcon(
                    answer['matched'] == true
                        ? AppGlyphs.checkCircle
                        : AppGlyphs.info,
                  ),
                  title: Text(
                    answer['matched'] == true
                        ? '${answer['name'] ?? answer['profileId']}'
                        : context.l10n.netProfileNone,
                  ),
                  subtitle: Text('${answer['reason'] ?? ''}'),
                ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, _) => PageIntroCard(text: '$error'),
          ),
          profiles.when(
            data: (list) => list.isEmpty
                ? PageIntroCard(text: context.l10n.netProfileEmpty)
                : generateSection(
                    title: context.l10n.netProfileList,
                    items: [
                      for (final profile in list)
                        ListItem(
                          leading: const GlyphIcon(AppGlyphs.profiles),
                          title: Text(profile.name),
                          subtitle: Text(
                            '${(profile.payload['networkMatch'] as Map?)?['types'] ?? const []} · '
                            '${profile.upstreamSet}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: context.l10n.netProfileDelete,
                            onPressed: () => ref
                                .read(automationControllerProvider)
                                .deleteProfile(profile.id),
                            icon: const GlyphIcon(AppGlyphs.remove),
                          ),
                        ),
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (error, _) => PageIntroCard(text: '$error'),
          ),
        ],
      ),
    );
  }

  static String _contextDetail(Map<String, Object?> network) {
    final parts = <String>[
      if (network['metered'] == true) 'metered',
      if (network['roaming'] == true) 'roaming',
      if ((network['ssid'] as String?)?.isNotEmpty ?? false) '${network['ssid']}',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final upstream = TextEditingController();
    final priority = TextEditingController(text: '100');
    final types = <String>{'wifi'};
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(context.l10n.netProfileAdd),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: context.l10n.netProfileName),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final type in const ['wifi', 'cellular', 'ethernet'])
                    FilterChip(
                      label: Text(type),
                      selected: types.contains(type),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          types.add(type);
                        } else {
                          types.remove(type);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: upstream,
                decoration: InputDecoration(
                  labelText: context.l10n.netProfileUpstreamSet,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priority,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.netProfilePriority,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.netProfileCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.netProfileSave),
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
            id: newAutomationId('net'),
            name: name.text.trim().isEmpty ? 'network' : name.text.trim(),
            payload: {
              'kind': 'network',
              'priority': int.tryParse(priority.text.trim()) ?? 100,
              'enabled': true,
              'networkMatch': {'types': types.toList()},
              'upstreamSet': upstream.text.trim(),
              'ruleGroupStates': const <String>[],
              'featureToggles': const <String, Object?>{},
            },
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
