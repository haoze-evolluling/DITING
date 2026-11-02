/// MITM root-CA state: `available` and `installed` are separate, and an untrusted CA disables
/// inspection.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/ca_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in `main()`; the default reports a missing certificate, true of any host without the
/// engine.
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

/// Current CA state plus the three page actions; they go through the controller to avoid a second
/// `inspect()`.
class CaCertificateController extends AsyncNotifier<CaCertificateState> {
  @override
  Future<CaCertificateState> build() async {
    ref.watch(caCertificateRevisionProvider);
    final service = ref.watch(caCertificateServiceProvider);
    final state = await _guard(service.inspect);
    _syncLegacyFlags(state);
    return state;
  }

  /// Deletes `ca.crt`/`ca.key` and mints a new pair, so `https_inspection_ready` drops.
  Future<CaCertificateState> regenerate() async {
    final service = ref.read(caCertificateServiceProvider);
    final state = await _guard(() => service.inspect(regenerate: true));
    _publish(state);
    return state;
  }

  /// Re-reads the CA without regenerating it, e.g. after the "install certificate" screen.
  Future<CaCertificateState> refresh() async {
    final service = ref.read(caCertificateServiceProvider);
    final state = await _guard(service.inspect);
    _publish(state);
    return state;
  }

  /// Hands the CA to the system installer; the failure text is what the page shows.
  Future<CaInstallResult> install() async {
    try {
      return await ref.read(caCertificateServiceProvider).install();
    } on MissingPluginException {
      return CaInstallResult.none(currentL10n.caChannelUnavailable);
    } on PlatformException catch (error) {
      return CaInstallResult.none(
        (error.message ?? '').trim().isEmpty ? currentL10n.caInstallUnavailable : error.message!,
      );
    }
  }

  /// Copies the CA into Download; needed when the system installer is missing.
  Future<CaSaveResult> saveToDownloads() async {
    try {
      return await ref.read(caCertificateServiceProvider).saveToDownloads();
    } on MissingPluginException {
      return CaSaveResult(saved: false, error: currentL10n.caChannelUnavailable);
    } on PlatformException catch (error) {
      return CaSaveResult(
        saved: false,
        error: (error.message ?? '').trim().isEmpty
            ? currentL10n.caDownloadDirUnavailable
            : error.message,
      );
    }
  }

  void _publish(CaCertificateState next) {
    state = AsyncData(next);
    _syncLegacyFlags(next);
    // SharedPreferences writes are unobservable; every reader must be invalidated.
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  /// Folds channel failures into the state; the CA page has an `error` row.
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

  /// Drops the master switch while the CA is untrusted; never bumps the legacy revision, which
  /// would loop.
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

final caCertificateStateProvider =
    AsyncNotifierProvider<CaCertificateController, CaCertificateState>(
      CaCertificateController.new,
    );

/// Reads the CA without throwing; false until the first inspect completes.
final caReadyProvider = Provider<bool>((ref) {
  return ref.watch(caCertificateStateProvider).value?.ready ?? false;
});
