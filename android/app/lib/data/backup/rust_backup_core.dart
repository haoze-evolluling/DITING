library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x314b4244;

class RustBackupCore {
  RustBackupCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustBackupCore? _instance;

  static RustBackupCore get instance => _instance ??= _load();

  static RustBackupCore _load() => RustBackupCore._(
    KernelCore.load(
      crate: 'diting-backup-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'backup core',
      entries: const ['export', 'import'],
    ),
  );

  Map<String, Object?> exportDocument(Map<String, Object?> request) =>
      _core.call(request, entry: 'export');

  Map<String, Object?> importDocument(Map<String, Object?> request) =>
      _core.call(request, entry: 'import');
}
