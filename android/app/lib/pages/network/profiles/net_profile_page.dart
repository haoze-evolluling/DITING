/// Network profiles (N1): show the live network context, the profile it resolves to, and the
/// configurable profiles. Wi-Fi / cellular / roaming / metered can each carry a different upstream
/// set, rule-group state and toggle set; the switch happens as the context changes.
library;

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/state/automation_providers.dart';
import 'package:diting_android/state/net_profile_providers.dart';
import 'package:diting_android/widgets/chip_row.dart';
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
    final draft = await showFloatingDialog<_NetProfileDraft>(
      context: context,
      child: const _NetProfileDialog(),
    );
    if (draft == null || !context.mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref
        .read(automationControllerProvider)
        .saveProfile(
          AutomationProfile(
            id: newAutomationId('net'),
            name: draft.name.isEmpty ? 'network' : draft.name,
            payload: {
              'kind': 'network',
              'priority': draft.priority,
              'enabled': true,
              'networkMatch': {'types': draft.types},
              'upstreamSet': draft.upstream,
              'ruleGroupStates': const <String>[],
              'featureToggles': const <String, Object?>{},
            },
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}

typedef _NetProfileDraft = ({
  String name,
  String upstream,
  int priority,
  List<String> types,
});

class _NetProfileDialog extends StatefulWidget {
  const _NetProfileDialog();

  @override
  State<_NetProfileDialog> createState() => _NetProfileDialogState();
}

class _NetProfileDialogState extends State<_NetProfileDialog> {
  final _name = TextEditingController();
  final _upstream = TextEditingController();
  final _priority = TextEditingController(text: '100');
  final _types = <String>{'wifi'};

  @override
  void dispose() {
    _name.dispose();
    _upstream.dispose();
    _priority.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop<_NetProfileDraft>((
      name: _name.text.trim(),
      upstream: _upstream.text.trim(),
      priority: int.tryParse(_priority.text.trim()) ?? 100,
      types: _types.toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: l10n.netProfileAdd,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.netProfileCancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.netProfileSave)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: l10n.netProfileName),
          ),
          ChipRow(
            children: [
              for (final type in const ['wifi', 'cellular', 'ethernet'])
                FilterPill(
                  label: type,
                  selected: _types.contains(type),
                  onPressed: () => setState(() {
                    if (_types.contains(type)) {
                      _types.remove(type);
                    } else {
                      _types.add(type);
                    }
                  }),
                ),
            ],
          ),
          TextField(
            controller: _upstream,
            decoration: InputDecoration(labelText: l10n.netProfileUpstreamSet),
          ),
          TextField(
            controller: _priority,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.netProfilePriority),
          ),
        ],
      ),
    );
  }
}
