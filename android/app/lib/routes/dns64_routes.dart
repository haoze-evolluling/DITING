import 'package:diting_android/pages/network/dns64_page.dart';
import 'package:diting_android/routes/page.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:go_router/go_router.dart';

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
