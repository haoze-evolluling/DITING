/// Disclaimer page, read-only; `initial_agreement_accepted` was accepted at first run.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_system.dart';
import 'package:diting_android/pages/system/disclaimer_content.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonScaffold(
      title: context.l10n.disclaimerTitle,
      body: PageBody(
        children: [
          const DisclaimerIntroCard(),
          const SizedBox(height: 12),
          ListHeader(title: context.l10n.aboutDisclaimerEntry),
          const InitialAgreementCard(),
          const SizedBox(height: 12),
          ListHeader(title: context.l10n.disclaimerTerms),
          for (final term in mockDisclaimerTerms(context.l10n))
            DisclaimerTermCard(term: term),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 8,
              children: [
                GlyphIcon(
                  AppGlyphs.gavel,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Text(
                    context.l10n.disclaimerSource,
                    style: context.listCaptionStyle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
