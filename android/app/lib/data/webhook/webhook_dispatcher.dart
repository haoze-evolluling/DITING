// ignore_for_file: prefer_initializing_formals

/// A11: signs and delivers automation/audit events to a user webhook with bounded retries.
///
/// The two policy decisions (signature, retry timing) come from `diting-webhook-core`; this file is
/// only the network loop around them. A transport is injected so the retry path is testable without
/// a real socket.
library;

import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/webhook/rust_webhook_core.dart';

/// One HTTP result; a transport throws on a socket error and returns the status on any response.
class WebhookHttpResponse {
  const WebhookHttpResponse(this.status);

  final int status;
}

abstract interface class WebhookTransport {
  /// Posts `body` with `headers` to [url]. Throws on a transport failure.
  Future<WebhookHttpResponse> post(
    Uri url,
    Map<String, String> headers,
    String body,
  );
}

/// `dart:io` implementation; only the caller decides whether the URL is allowed.
class IoWebhookTransport implements WebhookTransport {
  const IoWebhookTransport();

  @override
  Future<WebhookHttpResponse> post(
    Uri url,
    Map<String, String> headers,
    String body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(url);
      headers.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.write(body);
      final response = await request.close();
      await response.drain<void>();
      return WebhookHttpResponse(response.statusCode);
    } finally {
      client.close(force: true);
    }
  }
}

/// The outcome of one delivery, for the UI's "test" button and for logging.
class WebhookDeliveryResult {
  const WebhookDeliveryResult({
    required this.ok,
    required this.attempts,
    this.status,
    this.error,
  });

  final bool ok;
  final int attempts;
  final int? status;
  final String? error;

  String describe() {
    if (ok) return 'ok (HTTP $status, $attempts attempt${attempts == 1 ? '' : 's'})';
    return 'failed after $attempts attempt${attempts == 1 ? '' : 's'}'
        '${status != null ? ' (HTTP $status)' : ''}'
        '${error != null ? ': $error' : ''}';
  }
}

class WebhookDispatcher {
  WebhookDispatcher({
    WebhookTransport? transport,
    RustWebhookCore? core,
    Future<void> Function(Duration)? sleep,
    int maxAttempts = 3,
    int baseDelayMs = 1000,
    int maxDelayMs = 30000,
    int Function()? clockSeconds,
  }) : _transport = transport ?? const IoWebhookTransport(),
       _core = core ?? RustWebhookCore.instance,
       _sleep = sleep ?? Future<void>.delayed,
       _maxAttempts = maxAttempts,
       _baseDelayMs = baseDelayMs,
       _maxDelayMs = maxDelayMs,
       _clockSeconds =
           clockSeconds ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  final WebhookTransport _transport;
  final RustWebhookCore _core;
  final Future<void> Function(Duration) _sleep;
  final int _maxAttempts;
  final int _baseDelayMs;
  final int _maxDelayMs;
  final int Function() _clockSeconds;

  /// Signs and delivers [payload] as JSON, retrying transient failures up to `maxAttempts`.
  Future<WebhookDeliveryResult> deliver({
    required String url,
    required String secret,
    required Map<String, Object?> payload,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const WebhookDeliveryResult(
        ok: false,
        attempts: 0,
        error: 'invalid url',
      );
    }
    final body = jsonEncode(payload);
    int? lastStatus;
    String? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      final timestamp = _clockSeconds();
      final signature = _core.sign(
        secret: secret,
        body: body,
        timestamp: timestamp,
      );
      try {
        final response = await _transport.post(uri, {
          'X-Diting-Timestamp': '$timestamp',
          'X-Diting-Signature': signature,
          'User-Agent': 'DITING-Webhook/1',
        }, body);
        lastStatus = response.status;
        lastError = null;
        if (response.status >= 200 && response.status < 300) {
          return WebhookDeliveryResult(
            ok: true,
            attempts: attempt,
            status: response.status,
          );
        }
      } catch (error) {
        lastStatus = null;
        lastError = '$error';
      }
      final decision = _core.retry(
        attempt: attempt,
        status: lastStatus,
        baseMs: _baseDelayMs,
        maxMs: _maxDelayMs,
        maxAttempts: _maxAttempts,
      );
      if (!decision.retry) break;
      await _sleep(Duration(milliseconds: decision.delayMs));
    }
    return WebhookDeliveryResult(
      ok: false,
      attempts: _maxAttempts,
      status: lastStatus,
      error: lastError,
    );
  }
}
