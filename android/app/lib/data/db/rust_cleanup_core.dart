library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x314C4344;

class RustCleanupCore {
  RustCleanupCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustCleanupCore? _instance;

  static RustCleanupCore get instance => _instance ??= _load();

  static RustCleanupCore _load() => RustCleanupCore._(
    KernelCore.load(
      crate: 'diting-cleanup-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'cleanup core',
    ),
  );

  Map<String, Object?> plan() => call({'op': 'plan'});

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
