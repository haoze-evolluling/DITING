library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/ca_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final caCertificateServiceProvider = Provider<CaCertificateService>(
  (ref) => const UnavailableCaCertificateService(),
);

class CaCertificateRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final caCertificateRevisionProvider =
    NotifierProvider<CaCertificateRevision, int>(CaCertificateRevision.new);

class CaCertificateController extends AsyncNotifier<CaCertificateState> {
  @override
  Future<CaCertificateState> build() async {
    ref.watch(caCertificateRevisionProvider);
    final service = ref.watch(caCertificateServiceProvider);
    final state = await _guard(service.inspect);
    _syncLegacyFlags(state);
    return state;
  }

  Future<CaCertificateState> regenerate() async {
    final service = ref.read(caCertificateServiceProvider);
    final state = await _guard(() => service.inspect(regenerate: true));
    _publish(state);
    return state;
  }

  Future<CaCertificateState> refresh() async {
    final service = ref.read(caCertificateServiceProvider);
    final state = await _guard(service.inspect);
    _publish(state);
    return state;
  }

  Future<CaInstallResult> install() async {
    try {
      return await ref.read(caCertificateServiceProvider).install();
    } on MissingPluginException {
      return CaInstallResult.none(currentL10n.caChannelUnavailable);
    } on PlatformException catch (error) {
      return CaInstallResult.none(
        _platformMessageOr(error, currentL10n.caInstallUnavailable),
      );
    }
  }

  Future<CaSaveResult> saveToDownloads() async {
    try {
      return await ref.read(caCertificateServiceProvider).saveToDownloads();
    } on MissingPluginException {
      return CaSaveResult(
        saved: false,
        error: currentL10n.caChannelUnavailable,
      );
    } on PlatformException catch (error) {
      return CaSaveResult(
        saved: false,
        error: _platformMessageOr(error, currentL10n.caDownloadDirUnavailable),
      );
    }
  }

  void _publish(CaCertificateState next) {
    state = AsyncData(next);
    _syncLegacyFlags(next);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  Future<CaCertificateState> _guard(
    Future<CaCertificateState> Function() call,
  ) async {
    try {
      return await call();
    } on MissingPluginException catch (error) {
      return CaCertificateState(
        available: false,
        installed: false,
        error: currentL10n.caChannelUnavailableDetail(
          error.message ?? currentL10n.appListNotRegistered,
        ),
      );
    } on PlatformException catch (error) {
      final message = (error.message ?? '').trim();
      return CaCertificateState(
        available: false,
        installed: false,
        error: message.isEmpty
            ? currentL10n.caReadFailedCode(error.code)
            : currentL10n.caReadFailed(message),
      );
    }
  }

  void _syncLegacyFlags(CaCertificateState state) {
    final settings = ref.read(legacySettingsProvider);
    if (settings.httpsInspectionReady != state.ready) {
      settings.setHttpsInspectionReady(state.ready);
    }
    if (!state.ready && settings.httpInspectionEnabled) {
      settings.setHttpInspectionApps(
        packages: settings.httpInspectionPackages,
        enabled: false,
      );
    }
  }
}

String _platformMessageOr(PlatformException error, String fallback) {
  final message = error.message ?? '';
  return message.trim().isEmpty ? fallback : message;
}

final caCertificateStateProvider =
    AsyncNotifierProvider<CaCertificateController, CaCertificateState>(
      CaCertificateController.new,
    );

final caReadyProvider = Provider<bool>((ref) {
  return ref.watch(caCertificateStateProvider).value?.ready ?? false;
});
