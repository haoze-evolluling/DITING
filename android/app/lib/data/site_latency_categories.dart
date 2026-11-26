library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/icons/icons.dart';

const dashboardSiteCount = 4;

enum SiteCategory {
  search(TablerIcons.search),
  shopping(TablerIcons.shopping_bag),
  video(TablerIcons.video),
  music(TablerIcons.music),
  social(TablerIcons.user),
  developer(TablerIcons.code),
  game(TablerIcons.device_gamepad);

  const SiteCategory(this.icon);

  String label(AppL10n l10n) => switch (this) {
    SiteCategory.search => l10n.uiSearch,
    SiteCategory.shopping => l10n.siteCategoryShopping,
    SiteCategory.video => l10n.siteCategoryVideo,
    SiteCategory.music => l10n.siteCategoryMusic,
    SiteCategory.social => l10n.siteCategorySocial,
    SiteCategory.developer => l10n.siteCategoryDeveloper,
    SiteCategory.game => l10n.siteCategoryGame,
  };

  final IconData icon;
}
