library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x31565344;

class RustServicesCore {
  RustServicesCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustServicesCore? _instance;

  static RustServicesCore get instance => _instance ??= _load();

  static RustServicesCore _load() => RustServicesCore._(
    KernelCore.load(
      crate: 'diting-services-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'services core',
    ),
  );

  Map<String, Object?> catalog() => call({'op': 'services.catalog'});

  Map<String, Object?> expand({
    required List<String> serviceIds,
    String kind = 'block',
  }) => call({'op': 'services.expand', 'serviceIds': serviceIds, 'kind': kind});

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
