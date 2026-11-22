import 'dart:io';

/// 严格校验 CIDR：必须带 `/`，地址可解析，前缀在地址族范围内。
bool isCidrText(String input) {
  final text = input.trim();
  final slash = text.indexOf('/');
  if (slash <= 0 || slash != text.lastIndexOf('/')) return false;
  final address = text.substring(0, slash);
  final prefixText = text.substring(slash + 1);
  if (!_isPrefix(prefixText)) return false;
  final prefix = int.parse(prefixText);
  if (_isIpv4(address)) return prefix <= 32;
  if (address.contains('%') || address.contains(' ')) return false;
  final parsed = InternetAddress.tryParse(address);
  return parsed != null &&
      parsed.type == InternetAddressType.IPv6 &&
      prefix <= 128;
}

bool _isPrefix(String text) {
  if (text.isEmpty || !text.codeUnits.every((unit) => unit >= 0x30 && unit <= 0x39)) {
    return false;
  }
  return text.length == 1 || !text.startsWith('0');
}

bool _isIpv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    if (!_isPrefix(part)) return false;
    if (int.parse(part) > 255) return false;
  }
  return true;
}
