library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x31504F44;

class RustOutboundProxyCore {
  RustOutboundProxyCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustOutboundProxyCore? _instance;

  static RustOutboundProxyCore get instance => _instance ??= _load();

  static RustOutboundProxyCore _load() => RustOutboundProxyCore._(
    KernelCore.load(
      crate: 'diting-outbound-proxy-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'outbound proxy core',
    ),
  );

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

  String engineJson(Map<String, Object?> config) =>
      call({'op': 'engineJson', 'config': config})['json'] as String;

  List<String> effectiveTargets(Map<String, Object?> config) => [
    for (final value
        in call({'op': 'effectiveTargets', 'config': config})['values'] as List)
      value as String,
  ];

  String normalizeProtocol(String value) =>
      call({'op': 'normalizeProtocol', 'value': value})['value'] as String;

  String normalizeScope(String value) =>
      call({'op': 'normalizeScope', 'value': value})['value'] as String;

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
