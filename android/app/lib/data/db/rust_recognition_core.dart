/// The native recognition core: the Rust crate in `rust/diting-recognition-core`, loaded over
/// `dart:ffi`.
///
/// The library is required. [`RustRecognitionCore.instance`] throws when the artifact is missing,
/// the platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first member-list load instead of quietly running a
/// second copy of the validation or cache rules.
///
/// Payloads are JSON with the shared kernel header — `magic "DRM1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DRM1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x314D5244;

class RustRecognitionCore {
  RustRecognitionCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustRecognitionCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustRecognitionCore get instance => _instance ??= _load();

  static RustRecognitionCore _load() => RustRecognitionCore._(
    KernelCore.load(
      crate: 'diting-recognition-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'recognition core',
    ),
  );

  /// Cache keys, endpoints, size limits and retry policy; static for the process lifetime.
  Map<String, Object?> plan() => call({'op': 'plan'});

  /// Parses and validates one member-list document; `ok` is false with a localized `error`.
  Map<String, Object?> parse(String raw) => call({'op': 'parse', 'raw': raw});

  /// Empty or over-limit avatar bytes are rejected before they enter the memory/disk cache.
  bool avatarAccepted(int size) =>
      call({'op': 'avatarAccepted', 'size': size})['value'] as bool;

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
