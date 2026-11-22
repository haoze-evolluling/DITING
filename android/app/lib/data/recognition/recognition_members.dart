library;

import 'package:diting_android/data/db/rust_recognition_core.dart';

enum RecognitionAvatarFrame {
  rainbow;

  static RecognitionAvatarFrame? fromName(String? raw) => switch (raw) {
    'rainbow' => rainbow,
    _ => null,
  };
}

class RecognitionMember {
  const RecognitionMember({
    required this.name,
    this.avatarFileName,
    this.count = 1,
    this.frame,
  });

  final String name;

  final String? avatarFileName;

  final int count;

  final RecognitionAvatarFrame? frame;
}

class RecognitionMembers {
  const RecognitionMembers({required this.version, required this.sponsors});

  final int version;

  final List<RecognitionMember> sponsors;

  static const empty = RecognitionMembers(version: 0, sponsors: []);
}

List<RecognitionMember> _membersFromParsed(Object? raw) {
  final items = raw is List ? raw : const [];
  return List.unmodifiable([
    for (final item in items)
      RecognitionMember(
        name: (item as Map)['name'] as String,
        avatarFileName: item['avatarFileName'] as String?,
        count: (item['count'] as num?)?.toInt() ?? 1,
        frame: RecognitionAvatarFrame.fromName(item['frame'] as String?),
      ),
  ]);
}

RecognitionMembers parseRecognitionMembers(String raw) {
  final answer = RustRecognitionCore.instance.parse(raw);
  if (answer['ok'] != true) {
    throw FormatException(answer['error'] as String? ?? '名单配置无法解析');
  }
  return RecognitionMembers(
    version: (answer['version'] as num).toInt(),
    sponsors: _membersFromParsed(answer['sponsors']),
  );
}
