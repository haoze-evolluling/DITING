/// Data model for the sponsor / co-builder list; validation runs in
/// `rust/diting-recognition-core`, and any failure throws [FormatException] so callers keep the last
/// good cache.
library;

import 'package:diting_android/data/db/rust_recognition_core.dart';

class RecognitionMember {
  const RecognitionMember({
    required this.name,
    this.avatarFileName,
    this.count = 1,
  });

  final String name;

  /// Avatar file name; null means a placeholder is drawn.
  final String? avatarFileName;

  /// How many times this sponsor supported the project; 1 unless the cloud list says otherwise.
  /// Only sponsors carry it, and the row draws a `×N` badge when it is above one.
  final int count;
}

class RecognitionMembers {
  const RecognitionMembers({
    required this.version,
    required this.sponsors,
    required this.coBuilders,
  });

  final int version;

  final List<RecognitionMember> sponsors;

  final List<RecognitionMember> coBuilders;

  static const empty = RecognitionMembers(
    version: 0,
    sponsors: [],
    coBuilders: [],
  );
}

List<RecognitionMember> _membersFromParsed(Object? raw) {
  final items = raw is List ? raw : const [];
  return List.unmodifiable([
    for (final item in items)
      RecognitionMember(
        name: (item as Map)['name'] as String,
        avatarFileName: item['avatarFileName'] as String?,
        count: (item['count'] as num?)?.toInt() ?? 1,
      ),
  ]);
}

/// Parses and validates a list JSON; the kernel rejects a wrong root, mistyped field, duplicate
/// entry or bad avatar file name with a user-readable reason.
RecognitionMembers parseRecognitionMembers(String raw) {
  final answer = RustRecognitionCore.instance.parse(raw);
  if (answer['ok'] != true) {
    throw FormatException(answer['error'] as String? ?? '名单配置无法解析');
  }
  return RecognitionMembers(
    version: (answer['version'] as num).toInt(),
    sponsors: _membersFromParsed(answer['sponsors']),
    coBuilders: _membersFromParsed(answer['coBuilders']),
  );
}
