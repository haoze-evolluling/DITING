import 'package:diting_android/pages/appearance/appearance_color_page.dart';
import 'package:diting_android/pages/appearance/appearance_shared_pages.dart';
import 'package:diting_android/pages/appearance/font_family_page.dart';
import 'package:diting_android/pages/appearance/font_size_page.dart';
import 'package:diting_android/pages/appearance/launcher_icon_page.dart';
import 'package:diting_android/pages/appearance/settings_parity_pages.dart';
import 'package:diting_android/pages/appearance/theme_page.dart';
import 'package:diting_android/pages/system/developer_page.dart';
import 'package:diting_android/pages/system/integration_page.dart';
import 'package:diting_android/pages/system/ip_quality_page.dart';
import 'package:diting_android/pages/system/sponsor_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/navigator.dart';
import 'package:go_router/go_router.dart';

/// Appearance, settings sub pages and system routes.
abstract final class SystemPaths {
  static const theme = '/theme';
  static const dayNight = '/theme/day-night';
  static const colorStyle = '/theme/color';
  static const homeOpacity = '/theme/home-opacity';
  static const bottomBar = '/theme/bottom-bar';
  static const homeSentence = '/theme/home-sentence';
  static const notification = '/theme/notification';
  static const background = '/theme/background';

  /// Home-screen launcher icon style.
  static const launcherIcon = '/theme/launcher-icon';

  /// Font family. No upstream equivalent; kept at the user's request.
  static const fontFamily = '/font-family';

  /// Font size, a sub page of [fontFamily]. Upstream had a slider on the appearance page.
  static const fontSize = '/font-size';

  /// Foreground/background behaviour (upstream `FOREGROUND_BACKGROUND_SETTINGS`).
  static const foregroundBackground = '/settings/background';

  /// Language settings (upstream `LANGUAGE_SETTINGS`).
  static const language = '/settings/language';

  /// Home screen widget, deep link and automation guide.
  static const integration = '/settings/integration';

  /// Developer options hub. Upstream had no such page; it is the only entry
  /// to the retained pages and sits in the settings app bar.
  static const developer = '/developer';
  static const sponsor = '/sponsor';

  /// Retained page: no upstream UI, kept at the user's request.
  static const ipQuality = '/ip-quality';
}

/// Appearance, settings and system routes, assembled by `lib/router.dart`. All set
/// `parentNavigatorKey: rootNavigatorKey`: they are full pages covering the whole tree, so the
/// nested navigator would keep the bottom dock visible.
List<RouteBase> systemRoutes() => <RouteBase>[
  GoRoute(
    path: SystemPaths.theme,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ThemePage()),
  ),
  GoRoute(
    path: SystemPaths.dayNight,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ThemeDayNightPage()),
  ),
  GoRoute(
    path: SystemPaths.colorStyle,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ThemeColorPage()),
  ),
  GoRoute(
    path: SystemPaths.homeOpacity,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ThemeHomeOpacityPage()),
  ),
  GoRoute(
    path: SystemPaths.bottomBar,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ThemeBottomBarPage()),
  ),
  GoRoute(
    path: SystemPaths.homeSentence,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ThemeHomeSentencePage()),
  ),
  GoRoute(
    path: SystemPaths.notification,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ThemeNotificationPage()),
  ),
  GoRoute(
    path: SystemPaths.background,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ThemeBackgroundPage()),
  ),
  GoRoute(
    path: SystemPaths.launcherIcon,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const LauncherIconPage()),
  ),
  GoRoute(
    path: SystemPaths.fontFamily,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const FontFamilyPage()),
  ),
  GoRoute(
    path: SystemPaths.fontSize,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const FontSizePage()),
  ),

  GoRoute(
    path: SystemPaths.foregroundBackground,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const SettingsBackgroundPage()),
  ),
  GoRoute(
    path: SystemPaths.language,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const SettingsLanguagePage()),
  ),

  GoRoute(
    path: SystemPaths.integration,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const IntegrationPage()),
  ),

  GoRoute(
    path: SystemPaths.developer,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const DeveloperPage()),
  ),
  GoRoute(
    path: SystemPaths.sponsor,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const SponsorPage()),
  ),

  // Retained page.
  GoRoute(
    path: SystemPaths.ipQuality,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const IpQualityPage()),
  ),
];
