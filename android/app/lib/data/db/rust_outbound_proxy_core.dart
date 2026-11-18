/// The native outbound-proxy configuration core: the Rust crate in
/// `rust/diting-outbound-proxy-core`, loaded over `dart:ffi`.
///
/// SharedPreferences, the Keystore, PackageManager, HTTP and the localized sentences stay in
/// Dart/Kotlin; this core imports the engine's protocol/host/port/credential/scope rules and owns
/// the app package checks, target filtering and the engine JSON. The library is required:
/// [`RustOutboundProxyCore.instance`] throws when the artifact is missing, the platform is
/// unsupported or the ABI version differs, so a build that forgot
/// `python rust/build_android.py` fails the settings page instead of accepting a config the engine
/// would reject.
///
/// Payloads are JSON with the shared kernel header — `magic "DOP1" | abi` (see [KernelCore]).
library;

import 'package:diting_android/data/db/kernel_core.dart';

/// `"DOP1"` read as a little-endian u32; the first field of every payload.
const _payloadMagic = 0x31504F44;

class RustOutboundProxyCore {
  RustOutboundProxyCore._(this._core);

  final KernelCore _core;

  /// Resolved library path, surfaced in diagnostics.
  String get libraryPath => _core.libraryPath;

  static RustOutboundProxyCore? _instance;

  /// The loaded core; throws [StateError] when no usable artifact was found.
  static RustOutboundProxyCore get instance => _instance ??= _load();

  static RustOutboundProxyCore _load() => RustOutboundProxyCore._(
    KernelCore.load(
      crate: 'diting-outbound-proxy-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'outbound proxy core',
    ),
  );

  /// First rejected field as a stable token, or null when the config is acceptable.
  String? validationError(
    Map<String, Object?> config, {
    String? selfPackage,
    List<String>? installedPackages,
  }) =>
      call({
            'op': 'validate',
            'config': config,
            'selfPackage': selfPackage,
            'installedPackages': installedPackages,
          })['code']
          as String?;

  /// The exact JSON `Engine.configureOutboundProxy` decodes.
  String engineJson(Map<String, Object?> config) =>
      call({'op': 'engineJson', 'config': config})['json'] as String;

  /// Target packages after dropping blanks/the proxy app, deduplicated and sorted.
  List<String> effectiveTargets(Map<String, Object?> config) => [
    for (final value
        in call({'op': 'effectiveTargets', 'config': config})['values'] as List)
      value as String,
  ];

  /// Shared enum fallback: `socks5` / `http`, anything else becomes `socks5`.
  String normalizeProtocol(String value) =>
      call({'op': 'normalizeProtocol', 'value': value})['value'] as String;

  /// Shared enum fallback: `apps` exactly, anything else becomes `all`.
  String normalizeScope(String value) =>
      call({'op': 'normalizeScope', 'value': value})['value'] as String;

  /// One payload round trip; throws when the library rejects the operation.
  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
