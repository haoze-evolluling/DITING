library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x31504E44;

class RustNetprofileCore {
  RustNetprofileCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustNetprofileCore? _instance;

  static RustNetprofileCore get instance => _instance ??= _load();

  static RustNetprofileCore _load() => RustNetprofileCore._(
    KernelCore.load(
      crate: 'diting-netprofile-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'netprofile core',
    ),
  );

  Map<String, Object?> resolve({
    required Map<String, Object?> networkCtx,
    required List<Map<String, Object?>> profiles,
    String fallbackId = '',
  }) => call({
    'op': 'netprofile.resolve',
    'networkCtx': networkCtx,
    'profiles': profiles,
    'fallbackId': fallbackId,
  });

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
