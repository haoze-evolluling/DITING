/// The native IP-quality core: the Rust crate in `rust/diting-ip-quality-core`, loaded over
/// `dart:ffi`.
///
/// HTTP, timeouts, the user agent and the localized failure sentences stay in Dart; this core owns
/// the probe body, the three source replies, the type classifier and the report summary. The
/// library is required: [`RustIpQualityCore.instance`] throws when the artifact is missing, the
/// platform is unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails the check instead of quietly running a second set of
/// keywords.
///
/// Payloads are JSON with the shared kernel header — `magic "DIQ1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DIQ1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31514944;

class RustIpQualityCore {
  RustIpQualityCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustIpQualityCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustIpQualityCore get instance => _instance ??= _load();

  static RustIpQualityCore _load() => RustIpQualityCore._(
    KernelCore.load(
      crate: 'diting-ip-quality-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'ip quality core',
    ),
  );

  /// Reads the egress IP from a plain or `{"ip": "..."}` probe body; null means no address.
  String? parseProbe(String body) =>
      call({'op': 'parseProbe', 'body': body})['ip'] as String?;

  /// Same IP-shaped gate the checker used for a bare address body.
  bool isIpLike(String value) =>
      call({'op': 'ipLike', 'value': value})['value'] as bool;

  /// One source reply after the HTTP status arrived; status tokens are `命中` / `失败` / `限流`.
  Map<String, Object?> sourceResult({
    required String source,
    required int status,
    required String body,
  }) => call({
    'op': 'sourceResult',
    'source': source,
    'status': status,
    'body': body,
  });

  /// Majority type, severity tie-break, level, and the first non-empty organization/ASN.
  Map<String, Object?> summarize(
    String ip,
    List<Map<String, Object?>> sources,
  ) => call({'op': 'summarize', 'ip': ip, 'sources': sources});

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
