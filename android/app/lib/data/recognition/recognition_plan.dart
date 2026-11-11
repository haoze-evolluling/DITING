/// Cache keys, endpoints, size limits and retry policy from `rust/diting-recognition-core`.
///
/// Reading a missing field throws: an empty cache key or a zero limit would silently disable the
/// cache or reject every avatar.
library;

import 'package:diting_android/data/db/rust_recognition_core.dart';

class RecognitionPlan {
  RecognitionPlan._(this._raw);

  static final RecognitionPlan instance = RecognitionPlan._(
    RustRecognitionCore.instance.plan(),
  );

  final Map<String, Object?> _raw;

  String _string(String key) {
    final value = _raw[key];
    if (value is! String) {
      throw StateError('recognition core: missing "$key"');
    }
    return value;
  }

  int _int(String key) {
    final value = _raw[key];
    if (value is! num) {
      throw StateError('recognition core: missing "$key"');
    }
    return value.toInt();
  }

  String get container => _string('container');
  String get configKey => _string('configKey');
  String get savedAtKey => _string('savedAtKey');
  String get etagKey => _string('etagKey');
  String get membersUrl => _string('membersUrl');
  String get avatarBaseUrl => _string('avatarBaseUrl');
  int get maxConfigBytes => _int('maxConfigBytes');
  int get maxAvatarBytes => _int('maxAvatarBytes');
  int get refreshAttempts => _int('refreshAttempts');
  int get refreshDelayBaseMs => _int('refreshDelayBaseMs');
  int get avatarAttempts => _int('avatarAttempts');
  int get avatarDelayBaseMs => _int('avatarDelayBaseMs');
}
