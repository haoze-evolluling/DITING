library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x31504344;

class RustCaptiveCore {
  RustCaptiveCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustCaptiveCore? _instance;

  static RustCaptiveCore get instance => _instance ??= _load();

  static RustCaptiveCore _load() => RustCaptiveCore._(
    KernelCore.load(
      crate: 'diting-captive-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'captive core',
    ),
  );

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

  String? parseOption(String option) {
    final answer = call({'op': 'captive.parseOption', 'option': option});
    final url = answer['url'];
    return url is String && url.isNotEmpty ? url : null;
  }

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

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
