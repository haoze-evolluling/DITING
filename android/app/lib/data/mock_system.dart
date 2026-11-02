/// Disclaimer text shown by the disclaimer page.
library;

import 'package:diting_shared/app/l10n/l10n.dart';

class MockDisclaimerTerm {
  const MockDisclaimerTerm({required this.title, required this.content});

  final String title;
  final String content;
}

List<MockDisclaimerTerm> mockDisclaimerTerms(AppL10n l10n) => [
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm1Title,
    content: l10n.disclaimerTerm1Content,
  ),
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm2Title,
    content: l10n.disclaimerTerm2Content,
  ),
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm3Title,
    content: l10n.disclaimerTerm3Content,
  ),
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm4Title,
    content: l10n.disclaimerTerm4Content,
  ),
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm5Title,
    content: l10n.disclaimerTerm5Content,
  ),
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm6Title,
    content: l10n.disclaimerTerm6Content,
  ),
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm7Title,
    content: l10n.disclaimerTerm7Content,
  ),
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm8Title,
    content: l10n.disclaimerTerm8Content,
  ),
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm9Title,
    content: l10n.disclaimerTerm9Content,
  ),
  MockDisclaimerTerm(
    title: l10n.disclaimerTerm10Title,
    content: l10n.disclaimerTerm10Content,
  ),
];
