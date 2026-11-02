/// XOR masks plus Base64, byte-identical to the legacy `KeyObfuscator.kt`:
/// `agent_ai_providers_json` holds legacy ciphertext. Obfuscation, not encryption.
library;

import 'dart:convert';

const _ka = [0x4D, 0x1A, 0xC8, 0x37, 0x62, 0x9E, 0xFB, 0x54];
const _kb = [0x29, 0x6C, 0xD3, 0x8E, 0x71, 0x05, 0xBA, 0x4F];
const _kc = [0xBE, 0x34, 0x65, 0x8A, 0x71, 0x22, 0xD9, 0x46];

String sealApiKey(String plain) {
  if (plain.trim().isEmpty) return '';
  final source = utf8.encode(plain);
  final mixed = List<int>.generate(source.length, (index) {
    return (source[index] ^
            _ka[index % _ka.length] ^
            _kb[index % _kb.length] ^
            _kc[index % _kc.length]) &
        0xFF;
  });
  return base64.encode(mixed);
}

/// Restores an obfuscated key. Undecodable input yields an empty string instead of throwing, so one
/// bad row cannot break the whole provider list.
String openApiKey(String sealed) {
  if (sealed.trim().isEmpty) return '';
  try {
    final mixed = base64.decode(sealed);
    final plain = List<int>.generate(mixed.length, (index) {
      return (mixed[index] ^
              _ka[index % _ka.length] ^
              _kb[index % _kb.length] ^
              _kc[index % _kc.length]) &
          0xFF;
    });
    return utf8.decode(plain);
  } on FormatException {
    // Not valid Base64, or not a valid UTF-8 byte sequence.
    return '';
  }
}
