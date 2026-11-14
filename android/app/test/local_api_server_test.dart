import 'dart:io';

import 'package:diting_android/data/db/rust_localapi_core.dart';
import 'package:diting_android/data/network/local_api_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The FFI artifact exists on the Windows dev host built by `cargo build`; skip elsewhere.
  final available = Platform.isWindows;

  group('dispatch policy', () {
    late LocalApiServer server;

    setUp(() {
      server = LocalApiServer(core: RustLocalApiCore.instance, token: 'secret');
    });

    test('rejects a missing token', () {
      final response = server.dispatch(
        method: 'GET',
        path: '/status',
        remoteIp: '127.0.0.1',
      );
      expect(response.statusCode, 401);
    }, skip: !available);

    test('rejects a wrong token', () {
      final response = server.dispatch(
        method: 'GET',
        path: '/status',
        remoteIp: '127.0.0.1',
        providedToken: 'nope',
      );
      expect(response.statusCode, 401);
    }, skip: !available);

    test('a non-loopback client is forbidden', () {
      final response = server.dispatch(
        method: 'GET',
        path: '/status',
        remoteIp: '192.168.1.9',
        providedToken: 'secret',
      );
      expect(response.statusCode, 403);
    }, skip: !available);

    test('serves a known route with a valid token', () {
      final response = server.dispatch(
        method: 'GET',
        path: '/status',
        remoteIp: '127.0.0.1',
        providedToken: 'secret',
      );
      expect(response.statusCode, 200);
      expect(response.body, contains('status'));
    }, skip: !available);

    test('a known route is GET-only', () {
      final response = server.dispatch(
        method: 'POST',
        path: '/status',
        remoteIp: '127.0.0.1',
        providedToken: 'secret',
      );
      expect(response.statusCode, 405);
    }, skip: !available);

    test('an unknown route is a 404', () {
      final response = server.dispatch(
        method: 'GET',
        path: '/admin',
        remoteIp: '127.0.0.1',
        providedToken: 'secret',
      );
      expect(response.statusCode, 404);
    }, skip: !available);
  });

  group('live server', () {
    test('binds loopback and enforces the token over HTTP', () async {
      final server = LocalApiServer(
        core: RustLocalApiCore.instance,
        token: 'secret',
      );
      addTearDown(server.stop);
      final port = await server.start();
      final client = HttpClient();
      addTearDown(client.close);

      Future<HttpClientResponse> call({String? token}) async {
        final request = await client.get('127.0.0.1', port, '/status');
        if (token != null) {
          request.headers.set(localApiTokenHeader, token);
        }
        return request.close();
      }

      final authorized = await call(token: 'secret');
      expect(authorized.statusCode, 200);
      await authorized.drain<void>();

      final unauthorized = await call();
      expect(unauthorized.statusCode, 401);
      await unauthorized.drain<void>();
    }, skip: !available);
  });
}
