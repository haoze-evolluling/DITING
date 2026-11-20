library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x314D5244;

class RustRecognitionCore {
  RustRecognitionCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustRecognitionCore? _instance;

  static RustRecognitionCore get instance => _instance ??= _load();

  static RustRecognitionCore _load() => RustRecognitionCore._(
    KernelCore.load(
      crate: 'diting-recognition-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'recognition core',
    ),
  );

  Map<String, Object?> plan() => call({'op': 'plan'});

  Map<String, Object?> parse(String raw) => call({'op': 'parse', 'raw': raw});

  bool avatarAccepted(int size) =>
      call({'op': 'avatarAccepted', 'size': size})['value'] as bool;

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
