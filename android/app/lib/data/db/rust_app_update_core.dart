library;

import 'package:diting_android/data/db/kernel_core.dart';

const _payloadMagic = 0x31505544;

class RustAppUpdateCore {
  RustAppUpdateCore._(this._core);

  final KernelCore _core;

  String get libraryPath => _core.libraryPath;

  static RustAppUpdateCore? _instance;

  static RustAppUpdateCore get instance => _instance ??= _load();

  static RustAppUpdateCore _load() => RustAppUpdateCore._(
    KernelCore.load(
      crate: 'diting-app-update-core',
      payloadMagic: _payloadMagic,
      errorPrefix: 'app update core',
    ),
  );

  bool isNewerVersion(String remote, String current) =>
      call({
            'op': 'isNewerVersion',
            'remote': remote,
            'current': current,
          })['value']
          as bool;

  Map<String, Object?> parseLatestRelease(
    String payload,
    String currentVersion,
  ) => call({
    'op': 'parseLatestRelease',
    'payload': payload,
    'currentVersion': currentVersion,
  });

  Map<String, Object?> statusMessage(int status, String body) =>
      call({'op': 'statusMessage', 'status': status, 'body': body});

  Map<String, Object?> call(Map<String, Object?> request) =>
      _core.call(request);
}
