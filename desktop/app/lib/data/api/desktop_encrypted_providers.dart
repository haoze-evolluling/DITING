/// The encrypted DNS server's state and its four write paths.
///
/// Every endpoint answers with the whole status after a change, so the page adopts it directly; a
/// rejection keeps the previous status and returns the service's reason.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_encrypted_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopEncryptedState {
  const DesktopEncryptedState({
    this.status,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopEncryptedStatus? status;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => status != null && error != null;
}

class DesktopEncryptedNotifier extends Notifier<DesktopEncryptedState> {
  @override
  DesktopEncryptedState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopEncryptedState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final status = await client.encryptedStatus();
      if (ref.mounted) state = DesktopEncryptedState(status: status);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopEncryptedState(status: state.status, error: error);
      }
    }
  }

  /// The service merges the patch over its config and answers with the normalised status.
  Future<DesktopApiException?> configure(Map<String, Object?> patch) =>
      _write(
        () => ref.read(desktopApiClientProvider).configureEncryptedDns(patch),
      );

  Future<DesktopApiException?> generateCert(Map<String, Object?> params) =>
      _write(
        () => ref
            .read(desktopApiClientProvider)
            .generateEncryptedCert(params),
      );

  Future<DesktopApiException?> importCert({
    required String certPem,
    required String keyPem,
  }) => _write(
    () => ref
        .read(desktopApiClientProvider)
        .importEncryptedCert(certPem: certPem, keyPem: keyPem),
  );

  Future<DesktopApiException?> _write(
    Future<DesktopEncryptedStatus> Function() action,
  ) async {
    if (state.saving) return null;
    state = DesktopEncryptedState(status: state.status, saving: true);
    try {
      final status = await action();
      if (ref.mounted) state = DesktopEncryptedState(status: status);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopEncryptedState(status: state.status, error: error);
      }
      return error;
    }
  }
}

final desktopEncryptedProvider =
    NotifierProvider<DesktopEncryptedNotifier, DesktopEncryptedState>(
      DesktopEncryptedNotifier.new,
    );
