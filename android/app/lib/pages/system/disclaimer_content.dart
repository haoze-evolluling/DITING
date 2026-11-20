library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_system.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

class DisclaimerIntroCard extends StatelessWidget {
  const DisclaimerIntroCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Row(
              spacing: 10,
              children: [
                GlyphIcon(
                  AppGlyphs.gavel,
                  size: 26,
                  color: colorScheme.primary,
                ),
                Text(
                  context.l10n.disclaimerReadFirst,
                  style: AppTextRole.sectionTitle.of(context),
                ),
              ],
            ),
            Text(
              context.l10n.disclaimerIntro,
              style: AppTextRole.supportingText.of(context),
            ),
            InlineNotice(message: context.l10n.disclaimerLawful, glyphSize: 18),
          ],
        ),
      ),
    );
  }
}

/// Read verbatim from `InitialAgreementDialog.message`, with no rewriting.
class InitialAgreementCard extends StatelessWidget {
  const InitialAgreementCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: CommonCard(
        // The default 14 inset suits a one-line description, not a block of prose the card already
        // narrows by 16 per side. 18 is used instead, with line height 1.6.
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Row(
              spacing: 8,
              children: [
                GlyphIcon(
                  AppGlyphs.checkCircle,
                  size: 18,
                  color: colorScheme.success,
                ),
                Expanded(
                  child: Text(
                    context.l10n.disclaimerFirstRun,
                    style: AppTextRole.caption
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                MetaChip(label: context.l10n.disclaimerImmutable),
              ],
            ),
            Text(
              context.l10n.agreementMessage,
              style: AppTextRole.legalText
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class DisclaimerTermCard extends StatelessWidget {
  const DisclaimerTermCard({super.key, required this.term});

  final MockDisclaimerTerm term;

  @override
  Widget build(BuildContext context) {
    return SectionBlock(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(term.title, style: AppTextRole.bodyStrong.of(context)),
            Text(
              term.content,
              style: AppTextRole.legalText
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
