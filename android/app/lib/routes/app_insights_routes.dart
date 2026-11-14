import 'package:diting_android/pages/network/app_insights_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// U5 应用报告卡 / U6 连接地图。
abstract final class AppInsightsPaths {
  static const root = '/network/insights';
}

List<RouteBase> appInsightsRoutes() => [
  GoRoute(
    path: AppInsightsPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const AppInsightsPage()),
  ),
];
