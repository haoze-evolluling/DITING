import 'package:diting_android/pages/subscriptions/subscription_edit_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

abstract final class SubscriptionFormPaths {
  static const add = '/subscriptions/add';
  static const editPattern = '/subscriptions/edit/:id';

  static String editOf(int id) => '/subscriptions/edit/$id';

  static String addPrefilled(String url) =>
      Uri(path: add, queryParameters: {'url': url}).toString();
}

List<RouteBase> subscriptionFormRoutes() => [
  GoRoute(
    path: SubscriptionFormPaths.add,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => androidDefaultPage(
      state,
      SubscriptionEditPage(prefillUrl: state.uri.queryParameters['url']),
    ),
  ),
  GoRoute(
    path: SubscriptionFormPaths.editPattern,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => androidDefaultPage(
      state,
      SubscriptionEditPage(
        subscriptionId: int.tryParse(state.pathParameters['id'] ?? ''),
      ),
    ),
  ),
];
