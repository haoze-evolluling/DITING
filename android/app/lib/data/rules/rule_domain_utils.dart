library;

import 'dart:io';

final _domainLabel = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');

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

String? _toAsciiLower(String value) {
  var isAscii = true;
  for (final unit in value.codeUnits) {
    if (unit > 0x7f) {
      isAscii = false;
      break;
    }
  }
  if (isAscii) {
    for (final unit in value.codeUnits) {
      if (unit < 0x21 || unit == 0x7f) {
        return null;
      }
    }
    return value.toLowerCase();
  }
  try {
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
