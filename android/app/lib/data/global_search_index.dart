library;

import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/app/l10n/l10n.dart';

class GlobalSearchEntry {
  const GlobalSearchEntry({
    required this.title,
    required this.route,
    required this.group,
    this.subtitle = '',
    this.glyphName = 'search',
    this.keywords = const [],
  });

  final String title;
  final String subtitle;
  final String route;

  final String group;

  final String glyphName;

  final List<String> keywords;

  bool matches(String lowercaseQuery) =>
      title.toLowerCase().contains(lowercaseQuery) ||
      subtitle.toLowerCase().contains(lowercaseQuery) ||
      group.toLowerCase().contains(lowercaseQuery) ||
      keywords.any((keyword) => keyword.toLowerCase().contains(lowercaseQuery));
}

List<GlobalSearchEntry> _extraCommands(AppL10n l10n) => [
  GlobalSearchEntry(
    title: l10n.healthTitle,
    route: '/health',
    group: l10n.searchGroupTools,
    subtitle: l10n.healthIntro,
    glyphName: 'verified',
  ),
  GlobalSearchEntry(
    title: l10n.hitRankingTitle,
    route: '/logs/hit-ranking',
    group: l10n.searchGroupTools,
    subtitle: l10n.hitRankingEntrySubtitle,
    glyphName: 'rules',
  ),
  GlobalSearchEntry(
    title: l10n.ruleTestTitle,
    route: '/hub/rules/test',
    group: l10n.searchGroupTools,
    subtitle: l10n.ruleTestEnterSubtitle,
    glyphName: 'search',
  ),
  GlobalSearchEntry(
    title: l10n.blockPauseTitle,
    route: '/hub/rules/pause',
    group: l10n.searchGroupTools,
    subtitle: l10n.blockPauseEntrySubtitle,
    glyphName: 'block',
  ),
];

List<GlobalSearchEntry> buildGlobalSearchIndex(AppL10n l10n) => [
  for (final category in mockFeatureCategories(l10n))
    for (final card in category.cards)
      GlobalSearchEntry(
        title: card.title,
        subtitle: card.description,
        route: card.route,
        group: category.title,
        glyphName: card.glyphName,
        keywords: [card.description],
      ),
  ..._extraCommands(l10n),
];

List<GlobalSearchEntry> filterGlobalSearch(
  List<GlobalSearchEntry> entries,
  String query,
) {
  final lowercaseQuery = query.trim().toLowerCase();
  if (lowercaseQuery.isEmpty) return const [];
  return [
    for (final entry in entries)
      if (entry.matches(lowercaseQuery)) entry,
  ];
}
