/// Minimal WebDAV client: PROPFIND, MKCOL, PUT, GET. Credentials stay in memory.
library;

import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/http/request_user_agent.dart';
import 'package:diting_shared/app/l10n/l10n.dart';

class DavCredentials {
  const DavCredentials({
    required this.server,
    required this.username,
    required this.password,
    required this.path,
  });

  final String server;
  final String username;
  final String password;

  final String path;

  DavCredentials normalized() => DavCredentials(
    server: server.trim().replaceAll(RegExp(r'/+$'), ''),
    username: username.trim(),
    password: password,
    path: _normalizePath(path),
  );

  /// A missing leading slash makes PROPFIND hit the parent, so normalize both ends.
  static String _normalizePath(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '/diting/';
    if (!value.startsWith('/')) value = '/$value';
    if (!value.endsWith('/')) value = '$value/';
    return value;
  }

  String get directoryUrl => '$server$path';

  String fileUrl(String name) => '$server$path$name';

  /// Never logged or persisted.
  String get basicAuthHeader {
    final raw = '$username:$password';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }
}

class DavProbeResult {
  const DavProbeResult.ok({required this.created})
    : error = null,
      statusCode = null;

  const DavProbeResult.failed(String this.error, {this.statusCode})
    : created = false;

  final bool created;

  final String? error;

  final int? statusCode;

  bool get succeeded => error == null;
}

class DavClient {
  const DavClient({
    this.timeout = const Duration(seconds: 20),
    this.userAgent = appFallbackUserAgent,
  });

  /// 20s: a self-hosted LAN server answers quickly; beyond that it is unreachable.
  final Duration timeout;

  /// `/config/user-agents` override; some WebDAV gateways log or filter on UA.
  final String userAgent;

  Future<DavProbeResult> probe(DavCredentials rawCredentials) async {
    final credentials = rawCredentials.normalized();
    try {
      return await _withClient((client) async {
        final status = await _propfind(client, credentials);
        if (status == 207 || status == 200) {
          return const DavProbeResult.ok(created: false);
        }
        if (status == 404) {
          // A missing directory is normal on first use; failing to create it is not.
          final created = await _mkcol(client, credentials);
          return created
              ? const DavProbeResult.ok(created: true)
              : DavProbeResult.failed(currentL10n.davProbeNoWrite);
        }
        return DavProbeResult.failed(
          _statusMessage(status),
          statusCode: status,
        );
      });
    } on SocketException catch (error) {
      // Unreachable address, DNS failure and closed port look alike to users.
      return DavProbeResult.failed(currentL10n.davProbeConnect(error.message));
    } on HandshakeException {
      return DavProbeResult.failed(currentL10n.davProbeTls);
    } on HttpException {
      return DavProbeResult.failed(currentL10n.davProbeHttp);
    }
  }

  Future<DavProbeResult> putText(
    DavCredentials rawCredentials, {
    required String name,
    required String content,
  }) async {
    final credentials = rawCredentials.normalized();
    try {
      return await _withClient((client) async {
        final request = await _openRequest(
          client,
          'PUT',
          credentials.fileUrl(name),
          credentials,
        );
        request.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        final bytes = utf8.encode(content);
        request.headers.contentLength = bytes.length;
        request.add(bytes);
        final response = await request.close().timeout(timeout);
        await response.drain<void>();
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return const DavProbeResult.ok(created: false);
        }
        return DavProbeResult.failed(
          _statusMessage(response.statusCode),
          statusCode: response.statusCode,
        );
      });
    } on SocketException catch (error) {
      return DavProbeResult.failed(currentL10n.davUploadConnect(error.message));
    } on HandshakeException {
      return DavProbeResult.failed(currentL10n.davUploadTls);
    }
  }

  Future<String?> getText(
    DavCredentials rawCredentials, {
    required String name,
  }) async {
    final credentials = rawCredentials.normalized();
    return _withClient((client) async {
      final request = await _openRequest(
        client,
        'GET',
        credentials.fileUrl(name),
        credentials,
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 404) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException(currentL10n.davDownloadHttp(response.statusCode));
      }
      return await response.transform(utf8.decoder).join().timeout(timeout);
    });
  }

  /// One client per operation; it is force-closed so an abandoned socket cannot outlive the call.
  Future<T> _withClient<T>(Future<T> Function(HttpClient client) action) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await action(client);
    } finally {
      client.close(force: true);
    }
  }

  /// Opens [url] with the headers every WebDAV request shares.
  Future<HttpClientRequest> _openRequest(
    HttpClient client,
    String method,
    String url,
    DavCredentials credentials,
  ) async {
    final request = await client
        .openUrl(method, Uri.parse(url))
        .timeout(timeout);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      credentials.basicAuthHeader,
    );
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    return request;
  }

  Future<int> _propfind(HttpClient client, DavCredentials credentials) async {
    final request = await _openRequest(
      client,
      'PROPFIND',
      credentials.directoryUrl,
      credentials,
    );
    // Depth 0 asks for this resource only; no child listing is needed.
    request.headers.set('Depth', '0');
    request.headers.contentType = ContentType('application', 'xml');
    final body = utf8.encode(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getlastmodified/>'
      '</d:prop></d:propfind>',
    );
    request.headers.contentLength = body.length;
    request.add(body);
    final response = await request.close().timeout(timeout);
    await response.drain<void>();
    return response.statusCode;
  }

  Future<bool> _mkcol(HttpClient client, DavCredentials credentials) async {
    final request = await _openRequest(
      client,
      'MKCOL',
      credentials.directoryUrl,
      credentials,
    );
    request.headers.contentLength = 0;
    final response = await request.close().timeout(timeout);
    await response.drain<void>();
    // 201 means created; 405 means it already exists, which is fine under races.
    return response.statusCode == 201 || response.statusCode == 405;
  }

  String _statusMessage(int status) => switch (status) {
    401 => currentL10n.davStatus401,
    403 => currentL10n.davStatus403,
    404 => currentL10n.davStatus404,
    405 => currentL10n.davStatus405,
    409 => currentL10n.davStatus409,
    507 => currentL10n.davStatus507,
    >= 500 => currentL10n.davStatus5xx(status),
    _ => currentL10n.davStatusOther(status),
  };
}
