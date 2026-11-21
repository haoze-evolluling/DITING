import 'package:diting_android/pages/appearance/appearance_color_page.dart';
import 'package:diting_android/pages/appearance/appearance_shared_pages.dart';
import 'package:diting_android/pages/appearance/feedback_motion_page.dart';
import 'package:diting_android/pages/appearance/font_family_page.dart';
import 'package:diting_android/pages/appearance/font_size_page.dart';
import 'package:diting_android/pages/appearance/launcher_icon_page.dart';
import 'package:diting_android/pages/appearance/settings_parity_pages.dart';
import 'package:diting_android/pages/appearance/theme_page.dart';
import 'package:diting_android/pages/system/developer_page.dart';
import 'package:diting_android/pages/system/ip_quality_page.dart';
import 'package:diting_android/pages/system/sponsor_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/navigator.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

abstract final class SystemPaths {
  static const theme = '/theme';
  static const dayNight = '/theme/day-night';
  static const colorStyle = '/theme/color';
  static const homeOpacity = '/theme/home-opacity';
  static const bottomBar = '/theme/bottom-bar';
  static const homeSentence = '/theme/home-sentence';
  static const notification = '/theme/notification';
  static const background = '/theme/background';
  static const feedbackMotion = '/theme/feedback-motion';

  static const launcherIcon = '/theme/launcher-icon';

  static const fontFamily = '/font-family';

  static const fontSize = '/font-size';

  static const foregroundBackground = '/settings/background';

  static const language = '/settings/language';

  static const developer = '/developer';
  static const sponsor = '/sponsor';

  static const ipQuality = '/ip-quality';
}

GoRoute _route(String path, Widget page) => GoRoute(
  path: path,
  parentNavigatorKey: rootNavigatorKey,
  pageBuilder: (context, state) => androidDefaultPage(state, page),
);

List<RouteBase> systemRoutes() => [
  _route(SystemPaths.theme, const ThemePage()),
  _route(SystemPaths.dayNight, const ThemeDayNightPage()),
  _route(SystemPaths.colorStyle, const ThemeColorPage()),
  _route(SystemPaths.homeOpacity, const ThemeHomeOpacityPage()),
  _route(SystemPaths.bottomBar, const ThemeBottomBarPage()),
  _route(SystemPaths.homeSentence, const ThemeHomeSentencePage()),
  _route(SystemPaths.notification, const ThemeNotificationPage()),
  _route(SystemPaths.background, const ThemeBackgroundPage()),
  _route(SystemPaths.feedbackMotion, const ThemeFeedbackMotionPage()),
  _route(SystemPaths.launcherIcon, const LauncherIconPage()),
  _route(SystemPaths.fontFamily, const FontFamilyPage()),
  _route(SystemPaths.fontSize, const FontSizePage()),
  _route(SystemPaths.foregroundBackground, const SettingsBackgroundPage()),
  _route(SystemPaths.language, const SettingsLanguagePage()),
  _route(SystemPaths.developer, const DeveloperPage()),
  _route(SystemPaths.sponsor, const SponsorPage()),
  _route(SystemPaths.ipQuality, const IpQualityPage()),
];
