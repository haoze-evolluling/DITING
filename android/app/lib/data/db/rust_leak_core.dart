/// The native DNS-leak evaluator: the Rust crate in `rust/diting-leak-core`, loaded over `dart:ffi`.
///
/// The probe (a fingerprint TXT query and the tunnel's egress counters) is platform I/O and stays in
/// Kotlin/Dart; this bridge only hands the normalized outcome to the crate, which owns the
/// pass / leak / unknown verdict so the page and the health score share one implementation.
///
/// Payloads are JSON with the shared kernel header — `magic "DLK1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DLK1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x314B4C44;

class RustLeakCore {
  RustLeakCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustLeakCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustLeakCore get instance => _instance ??= _load();

  static RustLeakCore _load() => RustLeakCore._(
    KernelCore.load(
      crate: 'diting-leak-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'leak core',
    ),
  );

  /// Judges one normalized probe: answers `status` (pass/leak/unknown) and `reason`.
  Map<String, Object?> evaluate({
    String? observedExitId,
    String? expectedExitId,
    bool plaintextDnsSeen = false,
    bool? usedConfiguredUpstream,
  }) => call({
    'op': 'leak.evaluate',
    'probe': {
      'observedExitId': observedExitId,
      'expectedExitId': expectedExitId,
      'plaintextDnsSeen': plaintextDnsSeen,
      'usedConfiguredUpstream': usedConfiguredUpstream,
    },
  });

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
