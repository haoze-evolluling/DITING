/// The native app-update core: the Rust crate in `rust/diting-app-update-core`, loaded over
/// `dart:ffi`.
///
/// The library is required. [`RustAppUpdateCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails on the first update check instead of quietly running a
/// second copy of the version comparison, release parsing or status classification.
///
/// Payloads are JSON with the shared kernel header — `magic "DUP1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DUP1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31505544;

class RustAppUpdateCore {
  RustAppUpdateCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustAppUpdateCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustAppUpdateCore get instance => _instance ??= _load();

  static RustAppUpdateCore _load() => RustAppUpdateCore._(
    KernelCore.load(
      crate: 'diting-app-update-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'app update core',
    ),
  );

  /// Component-wise integer comparison; unparseable versions are never newer.
  bool isNewerVersion(String remote, String current) =>
      call({
            'op': 'isNewerVersion',
            'remote': remote,
            'current': current,
          })['value']
          as bool;

  /// Parses one `releases/latest` body; the answer is `available`, `upToDate` or `error`.
  Map<String, Object?> parseLatestRelease(
    String payload,
    String currentVersion,
  ) => call({
    'op': 'parseLatestRelease',
    'payload': payload,
    'currentVersion': currentVersion,
  });

  /// Classifies a non-200 response; the caller maps the kind back to a localized message.
  Map<String, Object?> statusMessage(int status, String body) =>
      call({'op': 'statusMessage', 'status': status, 'body': body});

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
