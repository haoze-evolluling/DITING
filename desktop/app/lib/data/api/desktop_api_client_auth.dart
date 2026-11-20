library;

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_auth_models.dart';

extension DesktopAuthApi on DesktopApiClient {
  Future<DesktopAuthStatus> authStatus() async =>
      DesktopAuthStatus.fromJson(await getJson('/api/v1/auth/status'));

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
