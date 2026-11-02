/// Data model and validation for the sponsor / co-builder list; any failure throws
/// [FormatException] so callers keep the last good cache.
library;

import 'dart:convert';

const recognitionMembersUrl =
    'https://raw.githubusercontent.com/haoze-evolluling/DITING/main/'
    'recognition_members.json';

const recognitionAvatarBaseUrl =
    'https://raw.githubusercontent.com/haoze-evolluling/DITING/main/avatars/';

/// Avatar file names must match `<lowercase/digit/underscore>_avatar.jpg`.
final _avatarFileNamePattern = RegExp(r'^[a-z0-9_]+_avatar\.jpg$');

class RecognitionMember {
  const RecognitionMember({required this.name, this.avatarFileName});

  final String name;

  /// Avatar file name; null means a placeholder is drawn.
  final String? avatarFileName;
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

/// Parses and validates a list JSON; throws [FormatException] on a wrong root, mistyped field,
/// duplicate entry or bad avatar file name.
RecognitionMembers parseRecognitionMembers(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    throw FormatException('名单配置不是合法 JSON：${error.message}');
  }
  if (decoded is! Map) {
    throw const FormatException('名单配置根节点必须是对象');
  }
  final version = decoded['version'];
  if (version is! int) {
    throw const FormatException('名单配置缺少版本号');
  }
  return RecognitionMembers(
    version: version,
    sponsors: _parseMembers(decoded['sponsors'], 'sponsors'),
    coBuilders: _parseMembers(decoded['coBuilders'], 'coBuilders'),
  );
}

List<RecognitionMember> _parseMembers(Object? raw, String field) {
  if (raw is! List) {
    throw FormatException('名单配置缺少 $field 数组');
  }
  final members = <RecognitionMember>[];
  final names = <String>{};
  final avatarFileNames = <String>{};
  for (final item in raw) {
    if (item is! Map) {
      throw FormatException('$field 中存在非对象元素');
    }
    final name = item['name'];
    if (name is! String || name.trim().isEmpty) {
      throw FormatException('$field 中存在空的成员名称');
    }
    final trimmed = name.trim();
    if (!names.add(trimmed)) {
      throw FormatException('$field 中存在重复成员：$trimmed');
    }
    final rawAvatar = item['avatarFileName'];
    String? avatarFileName;
    if (rawAvatar != null && rawAvatar is! String) {
      throw FormatException('$field 中 $trimmed 的头像文件名类型错误');
    }
    if (rawAvatar is String && rawAvatar.trim().isNotEmpty) {
      final value = rawAvatar.trim();
      if (!_avatarFileNamePattern.hasMatch(value)) {
        throw FormatException('$field 中 $trimmed 的头像文件名无效：$value');
      }
      if (!avatarFileNames.add(value)) {
        throw FormatException('$field 中存在重复头像文件：$value');
      }
      avatarFileName = value;
    }
    members.add(
      RecognitionMember(name: trimmed, avatarFileName: avatarFileName),
    );
  }
  return List.unmodifiable(members);
}
