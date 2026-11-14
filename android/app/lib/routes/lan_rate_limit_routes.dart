import 'package:diting_android/pages/network/lan_rate_limit_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// N9 LAN 客户端限速。
abstract final class LanRateLimitPaths {
  static const root = '/network/lan-rate-limit';
}

List<RouteBase> lanRateLimitRoutes() => [
  GoRoute(
    path: LanRateLimitPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const LanRateLimitPage()),
  ),
];
