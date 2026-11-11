/// Sponsor and co-builder lists (upstream `SponsorListScreen`), from remote JSON.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/hub/recognition_common.dart';
import 'package:material_ui/material_ui.dart';

class SponsorListPage extends StatelessWidget {
  const SponsorListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return RecognitionListPage(
      title: context.l10n.recognitionSponsorTitle,
      intro:
          context.l10n.recognitionSponsorIntro,
      sectionTitle: context.l10n.recognitionSponsorSection,
      select: (members) => members.sponsors,
      sortable: true,
    );
  }
}

class CoBuildersPage extends StatelessWidget {
  const CoBuildersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return RecognitionListPage(
      title: context.l10n.recognitionBuilderTitle,
      intro:
          context.l10n.recognitionBuilderIntro,
      sectionTitle: context.l10n.recognitionBuilderSection,
      select: (members) => members.coBuilders,
    );
  }
}
