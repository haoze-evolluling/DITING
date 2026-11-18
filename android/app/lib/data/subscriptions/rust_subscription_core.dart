/// The native subscription core: the Rust crate in `rust/diting-subscription-core`, loaded over
/// `dart:ffi`.
///
/// The library is required. [`RustSubscriptionCore.instance`] throws when the artifact is missing,
/// the platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first subscription page instead of quietly running a
/// second copy of the mirror/row/schedule rules.
///
/// Payloads are JSON and the header stays fixed — `magic "DSC1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DSC1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31435344;

/// The URI components kernel calls work on. `path` is the normalised path (`/` when empty) for
/// mirror building; name and validation rules use the raw `Uri.path`.
Map<String, Object?> uriParts(Uri? uri) => {
  'parsed': uri != null,
  'hasScheme': uri?.hasScheme ?? false,
  'scheme': uri?.scheme ?? '',
  'host': uri?.host ?? '',
  'path': uri?.path ?? '',
  'query': uri?.query ?? '',
};

class RustSubscriptionCore {
  RustSubscriptionCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustSubscriptionCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustSubscriptionCore get instance => _instance ??= _load();

  static RustSubscriptionCore _load() => RustSubscriptionCore._(
    KernelCore.load(
      crate: 'diting-subscription-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'subscription core',
    ),
  );

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
