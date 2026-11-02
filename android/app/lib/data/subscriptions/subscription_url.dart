/// Pure helpers for subscription URLs and content statistics; the placeholder set and
/// `{urlEncoded}` rules are frozen, since templates are persisted.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:convert';

const mirrorPlaceholders = <String>{
  '{url}',
  '{urlEncoded}',
  '{scheme}',
  '{host}',
  '{path}',
  '{pathAndQuery}',
};

/// Validates and normalizes a mirror template. Null means no template; a malformed one throws
/// [FormatException] for the edit panel to report.
String? normalizeMirrorTemplate(String? template) {
  final normalized = template?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  if (!mirrorPlaceholders.any(normalized.contains)) {
    throw FormatException(
      currentL10n.subsErrMirrorPlaceholder(
        '{url}、{urlEncoded}、{scheme}、{host}、{path} 或 {pathAndQuery}',
      ),
    );
  }
  buildMirrorUrl(normalized, 'https://example.com/rules.txt');
  return normalized;
}

/// Builds the mirror URL from a template. `{urlEncoded}` follows Java `URLEncoder` (keeps `*`,
/// encodes `~`), not `Uri.encodeComponent`.
String buildMirrorUrl(String template, String originalUrl) {
  final uri = Uri.tryParse(originalUrl);
  if (uri == null) {
    throw FormatException(currentL10n.subsErrRawUrlInvalid);
  }
  final path = uri.path.isEmpty ? '/' : uri.path;
  final pathAndQuery = uri.query.isEmpty ? path : '$path?${uri.query}';
  final result = template
      .replaceAll('{urlEncoded}', encodeForJavaUrlEncoder(originalUrl))
      .replaceAll('{url}', originalUrl)
      .replaceAll('{scheme}', uri.scheme)
      .replaceAll('{host}', uri.host)
      .replaceAll('{pathAndQuery}', pathAndQuery)
      .replaceAll('{path}', path);
  if (!result.startsWith('https://') && !result.startsWith('http://')) {
    throw FormatException(currentL10n.subsErrMirrorScheme);
  }
  return result;
}

/// Encodes like `java.net.URLEncoder` with `+` replaced by `%20`: `A-Z a-z 0-9` and `- _ . *` pass
/// through, other bytes become uppercase `%XX`.
String encodeForJavaUrlEncoder(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8BytesOf(value)) {
    final isPlain =
        (byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        byte == 0x2D ||
        byte == 0x5F ||
        byte == 0x2E ||
        byte == 0x2A;
    if (isPlain) {
      buffer.writeCharCode(byte);
    } else if (byte == 0x20) {
      // URLEncoder emits '+', which the caller would then replace with '%20'.
      buffer.write('%20');
    } else {
      buffer.write('%');
      buffer.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return buffer.toString();
}

String extractNameFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return url;
  }
  final path = uri.path;
  final fileName = path.substring(path.lastIndexOf('/') + 1);
  if (fileName.trim().isNotEmpty) {
    return fileName;
  }
  return uri.host.isNotEmpty ? uri.host : url;
}

/// Lexically counts effective lines (non-empty, non-comment): a download-layer figure, not the
/// imported rule count.
int countEffectiveRuleLines(String content) {
  var count = 0;
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('!') || line.startsWith('#') || line.startsWith('//')) {
      continue;
    }
    count++;
  }
  return count;
}

/// Basic URL validation: an absolute HTTP(S) URL with a host. Null means valid, otherwise the
/// returned text is shown to the user.
String? validateSubscriptionUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return currentL10n.subsErrEmpty;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return currentL10n.subsErrBadFormat;
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    return currentL10n.subsErrNotHttp;
  }
  if (uri.host.isEmpty) {
    return currentL10n.subsErrNoHost;
  }
  return null;
}

List<int> utf8BytesOf(String value) => const Utf8Codec().encode(value);
