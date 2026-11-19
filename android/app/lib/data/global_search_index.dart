/// U2 全局搜索/命令面板的索引：把功能中心的本地化卡片摊平成可搜索条目，再补几条常用直达命令。
///
/// 索引在运行时用当前 [AppL10n] 构建，因此切换语言后标题立即跟随；过滤是纯函数，便于单测。
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

  /// 分组名（功能中心分类名，或「常用命令」），面板里用作小标题。
  final String group;

  /// 目标页图标名（与功能中心卡片同一套 `AppGlyphs` 名称），列表行用它替代旧的统一搜索图标。
  final String glyphName;

  final List<String> keywords;

  bool matches(String lowercaseQuery) =>
      title.toLowerCase().contains(lowercaseQuery) ||
      subtitle.toLowerCase().contains(lowercaseQuery) ||
      group.toLowerCase().contains(lowercaseQuery) ||
      keywords.any((keyword) => keyword.toLowerCase().contains(lowercaseQuery));
}

/// 不属于功能中心卡片、但用户想直达的常用命令。
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

/// 全量索引：功能中心当前模式可见的卡片（按分类分组）+ 常用命令。
List<GlobalSearchEntry> buildGlobalSearchIndex(
  AppL10n l10n, {
  bool express = false,
}) => [
  for (final category in mockFeatureCategories(l10n))
    for (final card in category.cards)
      if (!express || card.expressVisible)
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

/// 按关键词过滤；空查询返回空列表（面板初始状态不显示全部）。
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
