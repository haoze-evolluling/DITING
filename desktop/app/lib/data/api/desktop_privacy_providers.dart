/// The privacy page's state: one read of `/status` and the five write paths that each patch their
/// own endpoint.
///
/// The service merges every patch over the config it holds, so a switch never rewrites an unrelated
/// field; after each write the status is re-read so the page shows what the service kept.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopPrivacyState {
  const DesktopPrivacyState({
    this.config,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopPrivacyConfig? config;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => config != null && error != null;
}

class DesktopPrivacyNotifier extends Notifier<DesktopPrivacyState> {
  @override
  DesktopPrivacyState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopPrivacyState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final status = await client.privacyConfig();
      if (ref.mounted) state = DesktopPrivacyState(config: status);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopPrivacyState(config: state.config, error: error);
      }
    }
  }

  Future<DesktopApiException?> setPrivacy(DesktopPrivacyConfig next) =>
      _write(() => ref.read(desktopApiClientProvider).configurePrivacy(next));

  Future<DesktopApiException?> setUnqualified(bool enabled) => _write(
    () => ref
        .read(desktopApiClientProvider)
        .configureUnqualified(enabled),
  );

  Future<DesktopApiException?> setEcs(DesktopPrivacyConfig next) => _write(
    () => ref.read(desktopApiClientProvider).configureEcs(next),
  );

  Future<DesktopApiException?> setRebind(DesktopPrivacyConfig next) => _write(
    () => ref.read(desktopApiClientProvider).configureRebind(next),
  );

  Future<DesktopApiException?> setHosts(DesktopPrivacyConfig next) => _write(
    () => ref.read(desktopApiClientProvider).configureHosts(next),
  );

  Future<DesktopApiException?> _write(Future<void> Function() action) async {
    if (state.saving) return null;
    state = DesktopPrivacyState(config: state.config, saving: true);
    try {
      await action();
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopPrivacyState(config: state.config, error: error);
      }
      return error;
    }
    await _load(ref.read(desktopApiClientProvider));
    return null;
  }
}

final desktopPrivacyProvider =
    NotifierProvider<DesktopPrivacyNotifier, DesktopPrivacyState>(
      DesktopPrivacyNotifier.new,
    );
