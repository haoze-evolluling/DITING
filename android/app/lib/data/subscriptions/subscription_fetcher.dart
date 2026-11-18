library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/http/request_user_agent.dart';
import 'package:diting_android/data/subscriptions/rust_subscription_core.dart';
import 'package:diting_android/data/subscriptions/subscription_url.dart';
import 'package:diting_shared/app/l10n/l10n.dart';

/// Threshold above which a subscription body is considered large, in bytes. A larger body is still
/// imported — the rule importer streams it a chunk at a time so the resident plan stays flat — but
/// the update flow warns the user it may slow the app down or cause other problems. The import path
/// materialises several full copies (decoded Dart objects, request/plan JSON, native buffers), so
/// the warning is the user's cue that a very large subscription is heavier than usual.
const int maxSubscriptionBytes = 2 * 1024 * 1024;

/// Result of one download. A non-null [error] means failure and the other fields are meaningless.
class SubscriptionFetchResult {
  const SubscriptionFetchResult({
    required this.outcome,
    this.lineCount = 0,
    this.byteLength = 0,
    this.etag,
    this.lastModified,
    this.error,
    this.requestedUrl,
    this.usedMirror = false,
    this.content,
    this.bodyBytes,
  });

  const SubscriptionFetchResult.notModified({
    this.etag,
    this.lastModified,
    this.requestedUrl,
    this.usedMirror = false,
  }) : outcome = SubscriptionFetchOutcome.notModified,
       lineCount = 0,
       byteLength = 0,
       error = null,
       content = null,
       bodyBytes = null;

  const SubscriptionFetchResult.failed(
    String message, {
    this.requestedUrl,
    this.usedMirror = false,
  }) : outcome = SubscriptionFetchOutcome.failed,
       lineCount = 0,
       byteLength = 0,
       etag = null,
       lastModified = null,
       error = message,
       content = null,
       bodyBytes = null;

  /// The download succeeded but the user declined to import an oversized body. Nothing was written,
  /// so the previous rules stay in place; this only marks the row as intentionally skipped.
  const SubscriptionFetchResult.skipped({
    this.requestedUrl,
    this.usedMirror = false,
    this.byteLength = 0,
  }) : outcome = SubscriptionFetchOutcome.skipped,
       lineCount = 0,
       etag = null,
       lastModified = null,
       error = null,
       content = null,
       bodyBytes = null;

  final SubscriptionFetchOutcome outcome;

  /// Lexical line count, not imported rules (see [countEffectiveRuleLines]).
  final int lineCount;
  final int byteLength;
  final String? etag;
  final String? lastModified;

  /// Readable failure text, shown to the user and stored as `importError`.
  final String? error;

  /// URL actually requested; differs after a mirror fallback.
  final String? requestedUrl;

  final bool usedMirror;

  final String? content;

  /// Raw UTF-8 body of a successful remote download, handed to the streaming parser without a
  /// `String` → bytes re-encode. Null for local files and non-content outcomes.
  final Uint8List? bodyBytes;

  bool get isSuccess => outcome == SubscriptionFetchOutcome.content;
  bool get isNotModified => outcome == SubscriptionFetchOutcome.notModified;
  bool get isFailure => outcome == SubscriptionFetchOutcome.failed;
  bool get isSkipped => outcome == SubscriptionFetchOutcome.skipped;
}

enum SubscriptionFetchOutcome { content, notModified, failed, skipped }

/// Replaceable so pages and tests never hit the network.
abstract class SubscriptionFetcher {
  /// Downloads the subscription in [record]. With [useValidators] false the request omits
  /// `If-None-Match` / `If-Modified-Since` (the 412 retry path).
  Future<SubscriptionFetchResult> fetch(
    SubscriptionRecord record, {
    bool useValidators = true,
  });
}

class HttpSubscriptionFetcher implements SubscriptionFetcher {
  HttpSubscriptionFetcher({
    HttpClient Function()? clientFactory,
    this.connectTimeout = const Duration(seconds: 30),
    this.readTimeout = const Duration(seconds: 60),
    this.userAgent = appFallbackUserAgent,
    this.onProgress,
    this.globalMirrorTemplate,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  final Duration connectTimeout;
  final Duration readTimeout;

  /// `/config/user-agents` override; servers that key on UA reject the default one.
  final String userAgent;

  /// Download progress: (bytes read, total bytes, or -1 when unknown).
  final void Function(int received, int total)? onProgress;

  /// Global mirror for rows without their own template; it always falls back to direct.
  final String? globalMirrorTemplate;

  @override
  Future<SubscriptionFetchResult> fetch(
    SubscriptionRecord record, {
    bool useValidators = true,
  }) async {
    // Order, mirror fallback and status rules live in the native core; this loop only drives the
    // HTTP stack and stops at the first target that reports instead of asking for a fallback.
    final plan = RustSubscriptionCore.instance.call({
      'op': 'fetch.targets',
      'record': {
        'url': record.url,
        'sourceType': record.sourceType.storageValue,
        'mirrorTemplate': record.mirrorTemplate,
        'mirrorFallback': record.mirrorFallback,
      },
      'globalTemplate': globalMirrorTemplate,
      'urlParts': mirrorUrlParts(Uri.tryParse(record.url)),
    });
    final targets = [
      for (final target in plan['targets'] as List? ?? const [])
        (target as Map).cast<String, Object?>(),
    ];
    SubscriptionFetchResult? last;
    for (final target in targets) {
      last = await _fetchOnce(
        record,
        target['url']! as String,
        useValidators: useValidators,
        usedMirror: target['usedMirror'] as bool? ?? false,
        allowFallback: target['allowFallback'] as bool? ?? false,
      );
      if (last != null) return last;
    }
    return last ??
        SubscriptionFetchResult.failed(
          currentL10n.subsErrUrlUnavailable,
          requestedUrl: record.url,
        );
  }

  /// Downloads once. Null only when a mirror failed and fallback is allowed.
  Future<SubscriptionFetchResult?> _fetchOnce(
    SubscriptionRecord record,
    String requestedUrl, {
    required bool useValidators,
    required bool usedMirror,
    required bool allowFallback,
  }) async {
    final client = _clientFactory()..connectionTimeout = connectTimeout;
    try {
      // A 412 means the validators are stale; retry once without them.
      var validators = useValidators;
      while (true) {
        final result = await _request(
          client,
          record,
          requestedUrl,
          useValidators: validators,
          usedMirror: usedMirror,
        );
        // Null sentinel: the server rejected the validators, retry without them.
        if (result != null) {
          return result;
        }
        validators = false;
      }
    } on TimeoutException {
      return _fallbackOr(
        SubscriptionFetchResult.failed(
          currentL10n.subsErrTimeout(readTimeout.inSeconds),
          requestedUrl: requestedUrl,
          usedMirror: usedMirror,
        ),
        allowFallback,
      );
    } on SocketException catch (error) {
      return _fallbackOr(
        SubscriptionFetchResult.failed(
          _networkErrorText(error),
          requestedUrl: requestedUrl,
          usedMirror: usedMirror,
        ),
        allowFallback,
      );
    } on HandshakeException {
      return _fallbackOr(
        SubscriptionFetchResult.failed(
          currentL10n.subsErrTls,
          requestedUrl: requestedUrl,
          usedMirror: usedMirror,
        ),
        allowFallback,
      );
    } on FormatException {
      return _fallbackOr(
        SubscriptionFetchResult.failed(
          currentL10n.subsErrBadFormat,
          requestedUrl: requestedUrl,
          usedMirror: usedMirror,
        ),
        allowFallback,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Single request. Null means 412: retry without the validators.
  Future<SubscriptionFetchResult?> _request(
    HttpClient client,
    SubscriptionRecord record,
    String requestedUrl, {
    required bool useValidators,
    required bool usedMirror,
  }) async {
    final request = await client.getUrl(Uri.parse(requestedUrl));
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    final headers = RustSubscriptionCore.instance.call({
      'op': 'fetch.headers',
      'etag': record.httpEtag,
      'lastModified': record.httpLastModified,
      'useValidators': useValidators,
    });
    if (headers['ifNoneMatch'] case final String etag) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }
    if (headers['ifModifiedSince'] case final String modified) {
      request.headers.set(HttpHeaders.ifModifiedSinceHeader, modified);
    }
    final response = await request.close().timeout(readTimeout);
    final etag = response.headers.value(HttpHeaders.etagHeader);
    final lastModified = response.headers.value(HttpHeaders.lastModifiedHeader);
    final verdict = RustSubscriptionCore.instance.call({
      'op': 'fetch.verdict',
      'status': response.statusCode,
      'useValidators': useValidators,
    });
    switch (verdict['kind']) {
      case 'retry':
        await response.drain<void>();
        return null;
      case 'notModified':
        await response.drain<void>();
        return SubscriptionFetchResult.notModified(
          etag: etag,
          lastModified: lastModified,
          requestedUrl: requestedUrl,
          usedMirror: usedMirror,
        );
      case 'failed':
        await response.drain<void>();
        return SubscriptionFetchResult.failed(
          'HTTP ${response.statusCode}',
          requestedUrl: requestedUrl,
          usedMirror: usedMirror,
        );
    }

    final body = await _readBody(response);
    if (body.isEmpty) {
      return SubscriptionFetchResult.failed(
        currentL10n.subsErrEmptyResponse,
        requestedUrl: requestedUrl,
        usedMirror: usedMirror,
      );
    }
    // A large body is imported straight from these bytes, so only decode it to a String (for the
    // display line count) when it is small enough to keep: retaining a second full-text copy of a
    // multi-megabyte subscription is exactly the copy the streaming import avoids.
    final large = body.length > maxSubscriptionBytes;
    final content = large
        ? null
        : const Utf8Decoder(allowMalformed: true).convert(body);
    return SubscriptionFetchResult(
      outcome: SubscriptionFetchOutcome.content,
      lineCount: content != null
          ? countEffectiveRuleLines(content)
          : _countEffectiveLinesBytes(body),
      byteLength: body.length,
      etag: etag,
      lastModified: lastModified,
      requestedUrl: requestedUrl,
      usedMirror: usedMirror,
      content: content,
      bodyBytes: body,
    );
  }

  /// After a mirror failure: null when fallback is allowed, else the failure.
  SubscriptionFetchResult? _fallbackOr(
    SubscriptionFetchResult failure,
    bool allowFallback,
  ) {
    if (allowFallback) {
      return null;
    }
    return failure;
  }

  /// Collects the body into a single packed `Uint8List`. A growable `List<int>` holds one boxed
  /// element per byte; for a multi-megabyte subscription that alone is several times the file
  /// size, and it was one of the full copies that pushed the process to its memory ceiling.
  Future<Uint8List> _readBody(HttpClientResponse response) async {
    final total = response.contentLength;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(readTimeout)) {
      builder.add(chunk);
      onProgress?.call(builder.length, total);
    }
    return builder.takeBytes();
  }

  static String _networkErrorText(SocketException error) {
    final code = error.osError?.message;
    return code == null || code.isEmpty
        ? currentL10n.subsErrUnreachable
        : currentL10n.subsErrUnreachableCode(code);
  }
}

/// Byte-level effective-line count for a large body that is not decoded to a String: non-empty after
/// trimming ASCII whitespace, and not a `!` / `#` / `//` comment. Matches `countEffectiveRuleLines`
/// closely enough for the display figure without materialising a second full-text copy.
int _countEffectiveLinesBytes(Uint8List bytes) {
  var count = 0;
  var start = 0;
  for (var i = 0; i <= bytes.length; i++) {
    if (i != bytes.length && bytes[i] != 0x0a) continue;
    var first = start;
    var last = i;
    while (first < last && _isAsciiSpace(bytes[first])) {
      first++;
    }
    while (last > first && _isAsciiSpace(bytes[last - 1])) {
      last--;
    }
    if (last > first) {
      final lead = bytes[first];
      final comment =
          lead == 0x21 /* ! */ ||
          lead == 0x23 /* # */ ||
          (lead == 0x2f /* / */ &&
              first + 1 < last &&
              bytes[first + 1] == 0x2f);
      if (!comment) count++;
    }
    start = i + 1;
  }
  return count;
}

bool _isAsciiSpace(int byte) =>
    byte == 0x20 ||
    byte == 0x09 ||
    byte == 0x0a ||
    byte == 0x0d ||
    byte == 0x0b ||
    byte == 0x0c;

/// Fallback when no implementation is injected: reports "unavailable" instead of throwing.
class UnavailableSubscriptionFetcher implements SubscriptionFetcher {
  const UnavailableSubscriptionFetcher();

  @override
  Future<SubscriptionFetchResult> fetch(
    SubscriptionRecord record, {
    bool useValidators = true,
  }) async => SubscriptionFetchResult.failed(currentL10n.subsErrUnsupported);
}
