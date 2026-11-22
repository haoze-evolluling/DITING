library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x31435344;

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

  String get libraryPath => _core.libraryPath;

  static RustSubscriptionCore? _instance;

  static RustSubscriptionCore get instance => _instance ??= _load();

  static RustSubscriptionCore _load() => RustSubscriptionCore._(
    KernelCore.load(
      crate: 'diting-subscription-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'subscription core',
    ),
  );

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
