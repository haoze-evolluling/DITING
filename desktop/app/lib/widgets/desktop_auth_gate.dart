/// The web console's gate: the desktop window goes straight to the app, a browser must first hold a
/// session.
///
/// The old desktop console did the same in `App.vue` — check `/auth/status`, show `LoginView` when the
/// browser has no session, and only then mount the console. The native desktop window is not web, so
/// it never authenticates and never sees a login form.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_auth_providers.dart';
import 'package:diting_desktop/pages/auth/desktop_login_page.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopAuthGate extends ConsumerWidget {
  const DesktopAuthGate({super.key, required this.child});

  /// The console itself: the router and every page behind it.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(desktopWebConsoleProvider)) return child;
    final auth = ref.watch(desktopAuthProvider);
    final Widget page;
    if (auth.checking) {
      page = const _Splash();
    } else if (auth.unreachable) {
      page = _Unreachable(
        error: auth.error,
        onRetry: () => ref.read(desktopAuthProvider.notifier).retry(),
      );
    } else if (!auth.signedIn) {
      page = const DesktopLoginPage();
    } else {
      return child;
    }
    // The gate replaces the router, so the login screen needs a navigator of its own: tooltips and
    // the background dialog both need an Overlay and a route to open on.
    return Navigator(
      pages: [MaterialPage<void>(child: page)],
      onDidRemovePage: (_) {},
    );
  }
}

/// The cold-start moment before `/auth/status` answers; the console is not mounted yet, so nothing
/// behind the gate can fire a request with a stale token.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Image.asset(
              dark ? 'packages/diting_shared/assets/images/icon_dark.png' : 'packages/diting_shared/assets/images/icon.png',
              width: 40,
              height: 40,
            ),
            Text(
              context.l10n.desktopLoginChecking,
              style: DashboardText.label(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.error, required this.onRetry});

  final DesktopApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unauthorized = error?.unauthorized ?? false;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NullStatus(
            illustration: unauthorized
                ? NullStatusIllustration.permission
                : NullStatusIllustration.error,
            label: l10n.desktopLoginUnreachable,
            description: unauthorized
                ? l10n.desktopBackendUnauthorizedBody
                : error?.message,
            action: FilledButton.tonal(
              onPressed: onRetry,
              child: Text(l10n.desktopLoginRetry),
            ),
          ),
        ),
      ),
    );
  }
}
