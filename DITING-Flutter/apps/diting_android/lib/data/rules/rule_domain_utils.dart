/// Domain normalization and literal IP checks; anything undecidable returns null so the rule counts
/// as invalid instead of never matching.
library;

import 'dart:io';

/// Sinkhole addresses: these hosts targets mean "block", not "rewrite".
const sinkholeAddresses = {'0', '0.0.0.0', '127.0.0.1', '::', '::1'};

final _domainLabel = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');

const validDnsTypes = {
  'A',
  'AAAA',
  'CNAME',
  'HTTPS',
  'SVCB',
  'TXT',
  'MX',
  'PTR',
  'SRV',
  'SOA',
  'NS',
  'ANY',
  'CAA',
  'DS',
  'DNSKEY',
};

/// Modifier prefixes that only matter for HTTP(S), not for DNS; such lines are valid rules the DNS
/// layer ignores.
const _webOnlyModifierPrefixes = [
  'domain=',
  '~domain=',
  'to=',
  '~to=',
  'method=',
  '~method=',
  'header=',
  '~header=',
  'redirect=',
  'redirect-rule=',
  'removeparam=',
  'removeheader=',
  'replace=',
  'urltransform=',
  'cookie=',
  'csp=',
  'permissions=',
  'jsonprune=',
  'xmlprune=',
  'referrerpolicy=',
  'reason=',
];

const _webOnlyModifierTokens = {
  'third-party',
  '~third-party',
  'strict-third-party',
  'strict-first-party',
  'match-case',
  'network',
  'document',
  '~document',
  'subdocument',
  '~subdocument',
  'script',
  '~script',
  'stylesheet',
  '~stylesheet',
  'image',
  '~image',
  'font',
  '~font',
  'media',
  '~media',
  'object',
  '~object',
  'xmlhttprequest',
  '~xmlhttprequest',
  'websocket',
  '~websocket',
  'ping',
  '~ping',
  'other',
  '~other',
  'popup',
  '~popup',
  'elemhide',
  'ehide',
  'generichide',
  'ghide',
  'specifichide',
  'shide',
  'genericblock',
  'urlblock',
  'content',
  'jsinject',
  'extension',
  'hls',
  'inline-script',
  'inline-font',
};

bool isWebOnlyModifier(String lower) {
  if (_webOnlyModifierTokens.contains(lower)) {
    return true;
  }
  return _webOnlyModifierPrefixes.any(lower.startsWith);
}

bool looksLikeLiteralIp(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 45) {
    return false;
  }
  if (trimmed == '0') {
    return true;
  }
  return InternetAddress.tryParse(trimmed) != null;
}

String? parseNumericAddressSafe(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 45) {
    return null;
  }
  final address = InternetAddress.tryParse(trimmed);
  return address?.address;
}

String? normalizeDomain(String value) {
  final candidate = value.trim().replaceFirst(RegExp(r'\.+$'), '');
  if (candidate.isEmpty ||
      candidate.contains('/') ||
      candidate.contains(':') ||
      candidate.contains(' ')) {
    return null;
  }
  final ascii = _toAsciiLower(candidate);
  if (ascii == null) {
    return null;
  }
  if (ascii.length > 253 || !ascii.contains('.') || looksLikeLiteralIp(ascii)) {
    return null;
  }
  for (final label in ascii.split('.')) {
    if (label.isEmpty || label.length > 63 || !_domainLabel.hasMatch(label)) {
      return null;
    }
  }
  return ascii;
}

String? normalizeWildcardDomain(String value) {
  final candidate = value.trim().replaceFirst(RegExp(r'\.+$'), '');
  if (candidate.isEmpty ||
      candidate.contains('/') ||
      candidate.contains(':') ||
      candidate.contains(' ')) {
    return null;
  }
  if (candidate == '*') {
    return '*';
  }
  final lower = candidate.toLowerCase();
  if (lower.length > 253) {
    return null;
  }
  for (final label in lower.split('.')) {
    if (label.isEmpty || label.length > 63) {
      return null;
    }
    for (final unit in label.codeUnits) {
      final isLower = unit >= 0x61 && unit <= 0x7a;
      final isDigit = unit >= 0x30 && unit <= 0x39;
      if (!isLower &&
          !isDigit &&
          unit != 0x2d &&
          unit != 0x2a &&
          unit != 0x5f) {
        return null;
      }
    }
  }
  return lower;
}

String? normalizeDomainForRewrite(String value) {
  final candidate = value.trim().replaceFirst(RegExp(r'\.+$'), '');
  if (candidate.isEmpty) {
    return null;
  }
  if (looksLikeLiteralIp(candidate)) {
    return parseNumericAddressSafe(candidate)?.toLowerCase();
  }
  return normalizeDomain(candidate);
}

String? _toAsciiLower(String value) {
  var isAscii = true;
  for (final unit in value.codeUnits) {
    if (unit > 0x7f) {
      isAscii = false;
      break;
    }
  }
  if (isAscii) {
    // ASCII domains still reject control characters and spaces.
    for (final unit in value.codeUnits) {
      if (unit < 0x21 || unit == 0x7f) {
        return null;
      }
    }
    return value.toLowerCase();
  }
  try {
    // `Uri.parse` applies IDNA to non-ASCII hosts; the returned host is punycode.
    final uri = Uri.parse('http://$value/');
    final host = uri.host;
    if (host.isEmpty) {
      return null;
    }
    return host.toLowerCase();
  } on FormatException {
    return null;
  }
}
