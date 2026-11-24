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

  final String? fingerprintSha256;

  final String? pem;

  final String? error;

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

enum CaInstallTarget {
  installer,

  settings,

  none,
}

class CaInstallResult {
  const CaInstallResult({required this.target, this.path, this.error});

  const CaInstallResult.none(String this.error)
    : target = CaInstallTarget.none,
      path = null;

  final CaInstallTarget target;

  final String? path;

  final String? error;

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

  final String? name;

  final String? error;

  static CaSaveResult fromMap(Map<Object?, Object?> map) => CaSaveResult(
    saved: map['saved'] == true,
    name: map['name'] as String?,
    error: map['error'] as String?,
  );
}

abstract class CaCertificateService {
  Future<CaCertificateState> inspect({bool regenerate = false});

  Future<CaInstallResult> install();

  Future<CaSaveResult> saveToDownloads();
}

class MethodChannelCaCertificateService implements CaCertificateService {
  MethodChannelCaCertificateService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(httpsInspectionChannelName);

  final MethodChannel _channel;

  static Map<Object?, Object?> _snapshot(Object? raw) =>
      raw is Map ? Map<Object?, Object?>.from(raw) : const {};

  @override
  Future<CaCertificateState> inspect({bool regenerate = false}) async {
    final raw = await _channel.invokeMethod<Object?>('inspectCa', {
      'regenerate': regenerate,
    });
    return CaCertificateState.fromMap(_snapshot(raw));
  }

  @override
  Future<CaInstallResult> install() async => CaInstallResult.fromMap(
    _snapshot(await _channel.invokeMethod<Object?>('installCa')),
  );

  @override
  Future<CaSaveResult> saveToDownloads() async => CaSaveResult.fromMap(
    _snapshot(await _channel.invokeMethod<Object?>('saveCa')),
  );
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
      CaSaveResult(saved: false, error: currentL10n.caChannelUnavailable);
}
