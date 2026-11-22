library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x31514944;

class RustIpQualityCore {
  RustIpQualityCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustIpQualityCore? _instance;

  static RustIpQualityCore get instance => _instance ??= _load();

  static RustIpQualityCore _load() => RustIpQualityCore._(
    KernelCore.load(
      crate: 'diting-ip-quality-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'ip quality core',
    ),
  );

  String? parseProbe(String body) =>
      call({'op': 'parseProbe', 'body': body})['ip'] as String?;

  bool isIpLike(String value) =>
      call({'op': 'ipLike', 'value': value})['value'] as bool;

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

  Map<String, Object?> summarize(
    String ip,
    List<Map<String, Object?>> sources,
  ) => call({'op': 'summarize', 'ip': ip, 'sources': sources});

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
