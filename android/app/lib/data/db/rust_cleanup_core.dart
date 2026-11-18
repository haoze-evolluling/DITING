/// The native cleanup core: the Rust crate in `rust/diting-cleanup-core`, loaded over `dart:ffi`.
///
/// The library is required. [`RustCleanupCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails before deleting anything instead of running a second copy
/// of the table list, WHERE clauses and preference keys.
///
/// Payloads are JSON with the shared kernel header — `magic "DCL1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DCL1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x314C4344;

class RustCleanupCore {
  RustCleanupCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustCleanupCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustCleanupCore get instance => _instance ??= _load();

  static RustCleanupCore _load() => RustCleanupCore._(
    KernelCore.load(
      crate: 'diting-cleanup-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'cleanup core',
    ),
  );

  /// The catalog document; the archive is static, so callers cache the parsed plan.
  Map<String, Object?> plan() => call({'op': 'plan'});

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
