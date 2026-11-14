import 'package:diting_android/pages/network/network_diagnostics_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// N6 DNS 泄漏检测与 Captive Portal。
abstract final class NetworkDiagnosticsPaths {
  static const root = '/network/diagnostics';
}

List<RouteBase> networkDiagnosticsRoutes() => [
  GoRoute(
    path: NetworkDiagnosticsPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const NetworkDiagnosticsPage()),
  ),
];
