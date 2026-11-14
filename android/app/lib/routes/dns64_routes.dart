import 'package:diting_android/pages/network/dns64_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// N8 DNS64。
abstract final class Dns64Paths {
  static const root = '/network/dns64';
}

List<RouteBase> dns64Routes() => [
  GoRoute(
    path: Dns64Paths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => androidDefaultPage(state, const Dns64Page()),
  ),
];
