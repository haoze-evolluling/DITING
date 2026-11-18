/// The native network-profile core: the Rust crate in `rust/diting-netprofile-core`, loaded over
/// `dart:ffi`.
///
/// Kotlin normalizes `ConnectivityManager` into the context this bridge sends; the crate owns
/// *which profile wins* and the effective configuration reference it returns. The library is
/// required: [`RustNetprofileCore.instance`] throws when the artifact is missing, the platform is
/// unsupported or the ABI version differs, so a build that forgot `python rust/build_android.py`
/// fails instead of resolving against a second Dart copy of the match rules.
///
/// Payloads are JSON with the shared kernel header — `magic "DNP1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DNP1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31504E44;

class RustNetprofileCore {
  RustNetprofileCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustNetprofileCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustNetprofileCore get instance => _instance ??= _load();

  static RustNetprofileCore _load() => RustNetprofileCore._(
    KernelCore.load(
      crate: 'diting-netprofile-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'netprofile core',
    ),
  );

  /// Resolves the effective profile for one network context.
  ///
  /// [profiles] are the profile documents (see `diting-netprofile-core`); [fallbackId] names the
  /// profile used when nothing matches. Answers `matched/profileId/upstreamSet/ruleGroupStates/
  /// featureToggles/reason`.
  Map<String, Object?> resolve({
    required Map<String, Object?> networkCtx,
    required List<Map<String, Object?>> profiles,
    String fallbackId = '',
  }) => call({
    'op': 'netprofile.resolve',
    'networkCtx': networkCtx,
    'profiles': profiles,
    'fallbackId': fallbackId,
  });

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
