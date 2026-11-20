library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x314B4C44;

class RustLeakCore {
  RustLeakCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustLeakCore? _instance;

  static RustLeakCore get instance => _instance ??= _load();

  static RustLeakCore _load() => RustLeakCore._(
    KernelCore.load(
      crate: 'diting-leak-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'leak core',
    ),
  );

  Map<String, Object?> evaluate({
    String? observedExitId,
    String? expectedExitId,
    bool plaintextDnsSeen = false,
    bool? usedConfiguredUpstream,
  }) => call({
    'op': 'leak.evaluate',
    'probe': {
      'observedExitId': observedExitId,
      'expectedExitId': expectedExitId,
      'plaintextDnsSeen': plaintextDnsSeen,
      'usedConfiguredUpstream': usedConfiguredUpstream,
    },
  });

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
