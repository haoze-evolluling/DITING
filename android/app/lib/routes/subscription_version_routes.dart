import 'package:diting_android/pages/hub/subscription_version_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// R6 订阅版本回滚。
abstract final class SubscriptionVersionPaths {
  static const root = '/hub/rules/versions';
}

List<RouteBase> subscriptionVersionRoutes() => [
  GoRoute(
    path: SubscriptionVersionPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const SubscriptionVersionPage()),
  ),
];
