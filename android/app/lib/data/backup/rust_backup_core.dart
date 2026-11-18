/// The native backup core: the Rust crate in `rust/diting-backup-core`, loaded over `dart:ffi`.
///
/// The library is required. [`RustBackupCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first export instead of quietly writing a file with
/// the old code.
///
/// The payload is JSON: the backup file itself is JSON, so a binary layout would only re-encode it
/// on both sides. The fixed header stays — `magic "DBK1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DBK1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x314b4244;

class RustBackupCore {
  RustBackupCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustBackupCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustBackupCore get instance => _instance ??= _load();

  static RustBackupCore _load() => RustBackupCore._(
    KernelCore.load(
      crate: 'diting-backup-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'backup core',
      entries: const ['export', 'import'],
    ),
  );

  /// Builds the backup document: `{nowMs, groups, fields}` in, `{content, included, counts,
  /// skipped}` out.
  Map<String, Object?> exportDocument(Map<String, Object?> request) =>
      _core.call(request, entry: 'export');

  /// Validates and merges a backup file: `{content, nowMs, hasDatabase, current}` in, the import
  /// plan out (see `rust/diting-backup-core/src/import.rs`).
  Map<String, Object?> importDocument(Map<String, Object?> request) =>
      _core.call(request, entry: 'import');
}
