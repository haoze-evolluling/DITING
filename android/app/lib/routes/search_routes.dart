import 'package:diting_android/pages/search/global_search_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// U2 全局搜索/命令面板。
abstract final class SearchPaths {
  static const root = '/search';
}

List<RouteBase> searchRoutes() => [
  GoRoute(
    path: SearchPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const GlobalSearchPage()),
  ),
];
