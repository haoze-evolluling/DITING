library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/icons/icons.dart';

const dashboardSiteCount = 4;

enum SiteCategory {
  search(AppGlyphs.search),
  shopping(AppGlyphs.shoppingBag),
  video(AppGlyphs.video),
  music(AppGlyphs.music),
  social(AppGlyphs.account),
  developer(AppGlyphs.code),
  game(AppGlyphs.gamepad);

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

  final Glyph glyph;
}
