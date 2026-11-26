library;

import 'package:diting_android/state/dns64_providers.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class Dns64Page extends ConsumerWidget {
  const Dns64Page({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(dns64EnabledProvider);
    final notifier = ref.read(dns64EnabledProvider.notifier);
    return CommonScaffold(
      title: l10n.dns64Title,
      body: PageBody(
        children: [
          generateSection(
            title: l10n.dns64Title,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.link),
                title: Text(l10n.dns64Enable),
                subtitle: Text(l10n.dns64EnableDesc),
                trailing: CommonSwitch(
                  value: enabled,
                  onChanged: notifier.setEnabled,
                  semanticLabel: l10n.dns64Enable,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
