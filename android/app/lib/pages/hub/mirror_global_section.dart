import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/db/mirror_template_repository.dart';
import 'package:diting_android/state/global_mirror_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class GlobalMirrorSection extends ConsumerWidget {
  const GlobalMirrorSection({super.key, required this.templates});

  final List<MirrorTemplateRecord> templates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mirror = ref.watch(globalMirrorProvider);
    final notifier = ref.read(globalMirrorProvider.notifier);
    final selected = templates
        .where((row) => row.template == mirror.template)
        .firstOrNull;
    return generateSection(
      title: context.l10n.mirrorGlobal,
      items: [
        ListItem.toggle(
          leading: const Icon(TablerIcons.flip_horizontal),
          title: Text(context.l10n.mirrorDefault),
          subtitle: Text(
            templates.isEmpty ? context.l10n.mirrorNeedTemplate : context.l10n.mirrorTemplateNote,
          ),
          value: mirror.enabled && templates.isNotEmpty,
          onChanged: templates.isEmpty
              ? null
              : (value) => notifier.setEnabled(
                  value,
                  fallbackTemplate: selected == null
                      ? templates.first.template
                      : null,
                ),
        ),
        if (mirror.enabled && templates.isNotEmpty)
          ListItem<MirrorTemplateRecord>.options(
            leading: const Icon(TablerIcons.flip_horizontal),
            title: Text(context.l10n.mirrorTemplate),
            subtitle: Text(
              mirror.template ?? templates.first.template,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            options: templates,
            value: selected ?? templates.first,
            textBuilder: (row) => row.name,
            onChanged: (row) => notifier.select(row.template),
          ),
      ],
      footer:
          context.l10n.mirrorNote,
    );
  }
}
