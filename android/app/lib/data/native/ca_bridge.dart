/// Dart side of `com.haoze.diting/https_inspection`: `available` means the engine produced a CA,
/// `installed` means its SHA-256 matches an entry in the Android user CA store, the only store an
/// app can write.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/services.dart';

const httpsInspectionChannelName = 'com.haoze.diting/https_inspection';

class CaCertificateState {
  const CaCertificateState({
    required this.available,
    required this.installed,
    this.fingerprintSha256,
    this.pem,
    this.error,
  });

  const CaCertificateState.missing()
    : available = false,
      installed = false,
      fingerprintSha256 = null,
      pem = null,
      error = null;

  final bool available;

  final bool installed;

  /// Uppercase colon-separated hex, the format 1.4.3 displayed verbatim.
  final String? fingerprintSha256;

  final String? pem;

  final String? error;

  /// Legacy `https_inspection_ready` flag: ready AND `ca_backend == "go-v1"`, set from [installed].
  bool get ready => available && installed;

  static CaCertificateState fromMap(Map<Object?, Object?> map) =>
      CaCertificateState(
        available: map['available'] == true,
        installed: map['installed'] == true,
        fingerprintSha256: map['fingerprintSha256'] as String?,
        pem: map['pem'] as String?,
        error: map['error'] as String?,
      );
}

/// What [CaCertificateService.install] managed to show.
enum CaInstallTarget {
  /// The system certificate installer accepted the staged file.
  installer,

  /// No installer activity: the security settings screen was opened instead, so the user has to
  /// pick the file from Download themselves.
  settings,

  /// Nothing could be opened.
  none,
}

class CaInstallResult {
  const CaInstallResult({required this.target, this.path, this.error});

  const CaInstallResult.none(String this.error)
    : target = CaInstallTarget.none,
      path = null;

  final CaInstallTarget target;

  /// Absolute path of the staged `.crt`, so the UI can tell the user where it is.
  final String? path;

  final String? error;

  bool get launched => target != CaInstallTarget.none;

  static CaInstallResult fromMap(Map<Object?, Object?> map) => CaInstallResult(
    target: switch (map['mode']) {
      'installer' => CaInstallTarget.installer,
      'settings' => CaInstallTarget.settings,
      _ => CaInstallTarget.none,
    },
    path: map['path'] as String?,
    error: map['error'] as String?,
  );
}

class CaSaveResult {
  const CaSaveResult({required this.saved, this.name, this.error});

  final bool saved;

  /// `Download/…` when MediaStore wrote it, otherwise an absolute app-private path.
  final String? name;

  final String? error;

  static CaSaveResult fromMap(Map<Object?, Object?> map) => CaSaveResult(
    saved: map['saved'] == true,
    name: map['name'] as String?,
    error: map['error'] as String?,
  );
}

abstract class CaCertificateService {
  /// Reads, and lazily generates, the CA; [regenerate] deletes `ca.crt`, `ca.key` and
  /// `mitm_blacklist.txt`, invalidating every certificate the device trusted.
  Future<CaCertificateState> inspect({bool regenerate = false});

  /// Hands the CA to the system certificate installer. Android offers no silent install, so this
  /// is the furthest an app can go on its own.
  Future<CaInstallResult> install();

  /// Copies the CA into the shared Download folder for manual installation later.
  Future<CaSaveResult> saveToDownloads();
}

class MethodChannelCaCertificateService implements CaCertificateService {
  MethodChannelCaCertificateService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(httpsInspectionChannelName);

  final MethodChannel _channel;

  @override
  Future<CaCertificateState> inspect({bool regenerate = false}) async {
    final raw = await _channel.invokeMethod<Object?>('inspectCa', {
      'regenerate': regenerate,
    });
    return CaCertificateState.fromMap(
      raw is Map ? Map<Object?, Object?>.from(raw) : const {},
    );
  }

  @override
  Future<CaInstallResult> install() async {
    final raw = await _channel.invokeMethod<Object?>('installCa');
    return CaInstallResult.fromMap(
      raw is Map ? Map<Object?, Object?>.from(raw) : const {},
    );
  }

  @override
  Future<CaSaveResult> saveToDownloads() async {
    final raw = await _channel.invokeMethod<Object?>('saveCa');
    return CaSaveResult.fromMap(
      raw is Map ? Map<Object?, Object?>.from(raw) : const {},
    );
  }
}

class UnavailableCaCertificateService implements CaCertificateService {
  const UnavailableCaCertificateService();

  @override
  Future<CaCertificateState> inspect({bool regenerate = false}) async =>
      const CaCertificateState.missing();

  @override
  Future<CaInstallResult> install() async =>
      CaInstallResult.none(currentL10n.caChannelUnavailable);

  @override
  Future<CaSaveResult> saveToDownloads() async =>
      CaSaveResult(
        saved: false,
        error: currentL10n.caChannelUnavailable,
      );
}
