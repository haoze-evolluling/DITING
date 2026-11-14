/// N8: the DNS64 page — one switch the engine turns into AAAA synthesis.
library;

import 'package:diting_android/state/dns64_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
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
          PageIntroCard(text: l10n.dns64Intro),
          // The card below has no section header to carry the gap, so it would butt straight
          // against the intro card; add the same 24 the header would.
          const ListSectionGap(),
          generateSection(
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.link),
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
