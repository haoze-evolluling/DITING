/// The LAN web console's state and its three writes.
///
/// Every write answers with a success flag, so each one re-reads `/web/status`: the service decides
/// the listening address and whether the firewall rule exists. A rejected write keeps the last
/// state and returns the reason.
library;

import 'dart:async';

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_web_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopWebState {
  const DesktopWebState({
    this.status,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopWebStatus? status;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => status != null && error != null;
}

class DesktopWebNotifier extends Notifier<DesktopWebState> {
  @override
  DesktopWebState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopWebState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final status = await client.webStatus();
      if (ref.mounted) state = DesktopWebState(status: status);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopWebState(status: state.status, error: error);
      }
    }
  }

  Future<DesktopApiException?> configure({
    required bool enabled,
    required int port,
  }) => _write(() async {
    await ref
        .read(desktopApiClientProvider)
        .configureWeb(enabled: enabled, port: port);
  });

  Future<DesktopApiException?> setFirewall(bool allowed) => _write(() async {
    await ref.read(desktopApiClientProvider).configureWebFirewall(allowed);
  });

  Future<DesktopApiException?> setPassword({
    required String username,
    required String oldPassword,
    required String newPassword,
    required bool initialized,
  }) => _write(() async {
    final client = ref.read(desktopApiClientProvider);
    if (initialized) {
      await client.changeAdminPassword(
        username: username,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
    } else {
      await client.setupAdmin(username: username, password: newPassword);
    }
  });

  Future<DesktopApiException?> _write(Future<void> Function() write) async {
    if (state.saving) return null;
    state = DesktopWebState(status: state.status, saving: true);
    try {
      await write();
      await _load(ref.read(desktopApiClientProvider));
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopWebState(status: state.status, error: error);
      }
      return error;
    }
  }
}

final desktopWebProvider = NotifierProvider<DesktopWebNotifier, DesktopWebState>(
  DesktopWebNotifier.new,
);
