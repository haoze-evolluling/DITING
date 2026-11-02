/// Site categories for the site-latency card and its detail page, plus the card's slot count.
///
/// Order here is the order the detail page stacks its groups.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/icons/icons.dart';

/// The dashboard card draws a 2x2 grid, so the user picks exactly this many sites.
const dashboardSiteCount = 4;

enum SiteCategory {
  search(AppGlyphs.search),
  shopping(AppGlyphs.star),
  video(AppGlyphs.photos),
  music(AppGlyphs.motion),
  social(AppGlyphs.account),
  developer(AppGlyphs.code),
  game(AppGlyphs.puzzle);

  const SiteCategory(this.glyph);

  String label(AppL10n l10n) => switch (this) {
    SiteCategory.search => l10n.uiSearch,
    SiteCategory.shopping => l10n.siteCategoryShopping,
    SiteCategory.video => l10n.siteCategoryVideo,
    SiteCategory.music => l10n.siteCategoryMusic,
    SiteCategory.social => l10n.siteCategorySocial,
    SiteCategory.developer => l10n.siteCategoryDeveloper,
    SiteCategory.game => l10n.siteCategoryGame,
  };

  /// Section header glyph; the board's own icons carry the brand, these carry the topic.
  final Glyph glyph;
}
