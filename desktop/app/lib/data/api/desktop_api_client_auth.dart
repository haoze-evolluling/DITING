/// The web console's auth and login-background API, split out of `desktop_api_client.dart` so that
/// file stays inside the line budget.
///
/// Same client, same transport: these are extension methods. `/auth/status`, `/auth/login`,
/// `/auth/setup` and `/auth/background` are public on the service; `/auth/logout` needs the session
/// token the login returned.
library;

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_auth_models.dart';

extension DesktopAuthApi on DesktopApiClient {
  Future<DesktopAuthStatus> authStatus() async =>
      DesktopAuthStatus.fromJson(await getJson('/api/v1/auth/status'));

  /// The service answers 401 for a wrong password, a lockout and a missing admin alike, so the caller
  /// re-reads [authStatus] to tell those cases apart instead of matching error text.
  Future<DesktopSession> signIn({
    required String username,
    required String password,
  }) async => DesktopSession.fromJson(
    await postJson(
      '/api/v1/auth/login',
      body: {'username': username, 'password': password},
    ),
  );

  Future<void> signOut() => postAction('/api/v1/auth/logout');

  Future<DesktopLoginBackground> loginBackground() async =>
      DesktopLoginBackground.fromJson(
        await getJson('/api/v1/auth/background'),
      );

  /// `url` may be an external address or a `data:image/...;base64,` payload; the service stores the
  /// latter itself. [adminPassword] is only needed by a remote browser that has no session yet.
  Future<DesktopLoginBackground> setLoginBackground({
    required String url,
    required int opacity,
    required int blur,
    String adminPassword = '',
  }) async => DesktopLoginBackground.fromJson(
    await postJson(
      '/api/v1/auth/background',
      body: {
        'url': url,
        'opacity': opacity,
        'blur': blur,
        if (adminPassword.isNotEmpty) 'adminPassword': adminPassword,
      },
    ),
  );

  Future<DesktopLoginBackground> resetLoginBackground({
    String adminPassword = '',
  }) async => DesktopLoginBackground.fromJson(
    await deleteJson(
      '/api/v1/auth/background',
      query: {if (adminPassword.isNotEmpty) 'adminPassword': adminPassword},
    ),
  );
}
