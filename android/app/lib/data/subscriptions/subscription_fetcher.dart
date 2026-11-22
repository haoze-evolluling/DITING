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

const int maxSubscriptionBytes = 2 * 1024 * 1024;

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

  final int lineCount;
  final int byteLength;
  final String? etag;
  final String? lastModified;

  final String? error;

  final String? requestedUrl;

  final bool usedMirror;

  final String? content;

  final Uint8List? bodyBytes;

  bool get isSuccess => outcome == SubscriptionFetchOutcome.content;
  bool get isNotModified => outcome == SubscriptionFetchOutcome.notModified;
  bool get isFailure => outcome == SubscriptionFetchOutcome.failed;
  bool get isSkipped => outcome == SubscriptionFetchOutcome.skipped;
}

enum SubscriptionFetchOutcome { content, notModified, failed, skipped }

abstract class SubscriptionFetcher {
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

  final String userAgent;

  final void Function(int received, int total)? onProgress;

  final String? globalMirrorTemplate;

  @override
  Future<SubscriptionFetchResult> fetch(
    SubscriptionRecord record, {
    bool useValidators = true,
  }) async {
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

  Future<SubscriptionFetchResult?> _fetchOnce(
    SubscriptionRecord record,
    String requestedUrl, {
    required bool useValidators,
    required bool usedMirror,
    required bool allowFallback,
  }) async {
    final client = _clientFactory()..connectionTimeout = connectTimeout;
    try {
      var validators = useValidators;
      while (true) {
        final result = await _request(
          client,
          record,
          requestedUrl,
          useValidators: validators,
          usedMirror: usedMirror,
        );
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

  SubscriptionFetchResult? _fallbackOr(
    SubscriptionFetchResult failure,
    bool allowFallback,
  ) {
    if (allowFallback) {
      return null;
    }
    return failure;
  }

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
          lead == 0x21   ||
          lead == 0x23   ||
          (lead == 0x2f   &&
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

class UnavailableSubscriptionFetcher implements SubscriptionFetcher {
  const UnavailableSubscriptionFetcher();

  @override
  Future<SubscriptionFetchResult> fetch(
    SubscriptionRecord record, {
    bool useValidators = true,
  }) async => SubscriptionFetchResult.failed(currentL10n.subsErrUnsupported);
}
