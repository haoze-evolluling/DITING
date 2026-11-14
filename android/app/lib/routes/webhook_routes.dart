import 'package:diting_android/pages/hub/webhook_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// A11 Webhook 通知。
abstract final class WebhookPaths {
  static const root = '/hub/rules/webhook';
}

List<RouteBase> webhookRoutes() => [
  GoRoute(
    path: WebhookPaths.root,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const WebhookPage()),
  ),
];
