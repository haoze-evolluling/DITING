library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/routes/config_routes.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_android/widgets/note_card.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class CustomResourcesConfigPage extends StatelessWidget {
  const CustomResourcesConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.customResourcesTitle,
      body: PageBody(
        children: [
          NoteCard(
            text:
                context.l10n.customResourcesNote,
            glyph: AppGlyphs.resources,
          ),
          generateSection(
            title: context.l10n.customResourcesSection,
            items: [
              // The config pages use the smaller 16 chevron and 20 glyph pair, as the rows here
              // always did; the defaults would move every row in this section.
              NavEntryRow(
                glyph: AppGlyphs.account,
                title: 'User-Agent',
                subtitle: context.l10n.devUserAgentBody,
                leadingSize: 20,
                chevronSize: 16,
                onPressed: () => context.push(ConfigPaths.userAgents),
              ),
              NavEntryRow(
                glyph: AppGlyphs.wifi,
                title: context.l10n.odTitle,
                subtitle: context.l10n.devOnDemandBody,
                leadingSize: 20,
                chevronSize: 16,
                onPressed: () => context.push(ConfigPaths.onDemand),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
