/// A10: the loopback-only, token-guarded local HTTP API.
///
/// The transport is an in-process [HttpServer] bound to `127.0.0.1`; every decision (loopback only,
/// token, route) is answered by the Rust kernel in `rust/diting-localapi-core`, so this file is
/// plumbing and cannot weaken the policy.
library;

import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/db/rust_localapi_core.dart';

/// The header the API reads its token from; matches `TOKEN_HEADER` in the Rust policy.
const localApiTokenHeader = 'X-Diting-Token';

/// The one address the API ever binds to.
const localApiBindAddress = '127.0.0.1';

/// A minimal HTTP response.
class LocalApiResponse {
  const LocalApiResponse(this.statusCode, this.body);

  final int statusCode;
  final String? body;
}

/// The local API server. Construct one per token; [start] binds loopback and [stop] closes it.
class LocalApiServer {
  LocalApiServer({RustLocalApiCore? core, this.token = ''})
    : _core = core ?? RustLocalApiCore.instance;

  final RustLocalApiCore _core;
  final String token;

  HttpServer? _server;

  /// The bound port while running.
  int? get port => _server?.port;

  bool get isRunning => _server != null;

  /// Binds `127.0.0.1:port` (0 picks an ephemeral port) and starts serving. Throws when the token is
  /// empty or the address is not loopback — both are refused before any socket is opened.
  Future<int> start({int port = 0}) async {
    if (token.trim().isEmpty) {
      throw StateError('local api: refusing to start without a token');
    }
    if (!_core.validateBind(localApiBindAddress)) {
      throw StateError('local api: refusing a non-loopback bind');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(_handle);
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = dispatch(
      method: request.method,
      path: request.uri.path,
      remoteIp: request.connectionInfo?.remoteAddress.address ?? '',
      providedToken: request.headers.value(localApiTokenHeader),
    );
    request.response.statusCode = response.statusCode;
    final body = response.body;
    if (body != null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(body);
    }
    await request.response.close();
  }

  /// The pure request handler: authorises, then resolves the route. Exposed so a unit test can drive
  /// it without a socket.
  LocalApiResponse dispatch({
    required String method,
    required String path,
    required String remoteIp,
    String? providedToken,
  }) {
    final decision = _core.authorize(
      bind: localApiBindAddress,
      clientIp: remoteIp,
      expectedToken: token,
      token: providedToken,
    );
    if (decision == 'not_loopback') return const LocalApiResponse(403, null);
    if (decision != 'allow') return const LocalApiResponse(401, null);

    final route = _core.route(method, path);
    switch (route['outcome']) {
      case 'found':
        return LocalApiResponse(
          200,
          jsonEncode({'ok': true, 'route': route['route']}),
        );
      case 'method_not_allowed':
        return const LocalApiResponse(405, null);
      default:
        return const LocalApiResponse(404, null);
    }
  }
}
