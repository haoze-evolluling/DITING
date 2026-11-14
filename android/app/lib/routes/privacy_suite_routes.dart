import 'package:diting_android/pages/network/privacy_suite_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// U10 隐私套件。
abstract final class PrivacySuitePaths {
  static const root = '/network/privacy';
}

List<RouteBase> privacySuiteRoutes() => [
  GoRoute(
    path: PrivacySuitePaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const PrivacySuitePage()),
  ),
];
