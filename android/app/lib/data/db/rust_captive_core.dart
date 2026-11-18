/// The native captive-portal evaluator: the Rust crate in `rust/diting-captive-core`, loaded over
/// `dart:ffi`.
///
/// The `generate_204` probe and the platform's capability bits are I/O and stay in Dart/Kotlin; this
/// bridge hands the normalized probe to the crate, which owns the open / portal / unknown judgement
/// and the "suspend blocking" gate.
///
/// Payloads are JSON with the shared kernel header — `magic "DCP1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DCP1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31504344;

class RustCaptiveCore {
  RustCaptiveCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustCaptiveCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustCaptiveCore get instance => _instance ??= _load();

  static RustCaptiveCore _load() => RustCaptiveCore._(
    KernelCore.load(
      crate: 'diting-captive-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'captive core',
    ),
  );

  /// Judges one `generate_204` probe: `state` (open/portal/unknown), `portalUrl`, `suspendBlocking`.
  Map<String, Object?> evaluate({
    int? statusCode,
    String? redirectUrl,
    bool? bodyMatchesExpected,
  }) => call({
    'op': 'captive.evaluate',
    'probe': {
      'statusCode': statusCode,
      'redirectUrl': redirectUrl,
      'bodyMatchesExpected': bodyMatchesExpected,
    },
  });

  /// Parses the RFC 8910 `Captive-Portal` option into a URL (`null` when it is not a usable http(s)
  /// URL).
  String? parseOption(String option) {
    final answer = call({'op': 'captive.parseOption', 'option': option});
    final url = answer['url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  /// Combines the platform capability bits with the probe verdict.
  Map<String, Object?> gate({
    required bool networkValidated,
    required bool captiveCapability,
    int? statusCode,
    String? redirectUrl,
    bool? bodyMatchesExpected,
  }) => call({
    'op': 'captive.gate',
    'networkValidated': networkValidated,
    'captiveCapability': captiveCapability,
    'probe': {
      'statusCode': statusCode,
      'redirectUrl': redirectUrl,
      'bodyMatchesExpected': bodyMatchesExpected,
    },
  });

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
