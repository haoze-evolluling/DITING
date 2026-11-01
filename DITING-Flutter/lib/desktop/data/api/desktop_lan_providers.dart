/// The LAN DNS page's state and its three writes.
///
/// Every write answers with a success flag only, so each one re-reads `/dns/lan`: the service decides
/// the listen addresses and whether a firewall rule exists. A rejected write keeps the last state and
/// returns the reason.
library;

import 'dart:async';

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_lan_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopLanState {
  const DesktopLanState({
    this.status,
    this.isLoading = false,
    this.saving = false,
    this.error,
  });

  final DesktopLanStatus? status;
  final bool isLoading;
  final bool saving;
  final DesktopApiException? error;

  bool get isStale => status != null && error != null;
}

class DesktopLanNotifier extends Notifier<DesktopLanState> {
  @override
  DesktopLanState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopLanState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final status = await client.lanStatus();
      if (ref.mounted) state = DesktopLanState(status: status);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopLanState(status: state.status, error: error);
      }
    }
  }

  /// Turning the service on asks for the 53/tcp+udp rule in the same call, as the console did.
  Future<DesktopApiException?> setAllowLan(bool allow) => _write(() async {
    await ref
        .read(desktopApiClientProvider)
        .configureLan(allowLan: allow, configureFirewall: allow);
  });

  Future<DesktopApiException?> setFirewall(bool allowed) => _write(() async {
    await ref.read(desktopApiClientProvider).configureLanFirewall(allowed);
  });

  Future<DesktopApiException?> _write(Future<void> Function() write) async {
    if (state.saving) return null;
    state = DesktopLanState(status: state.status, saving: true);
    try {
      await write();
      await _load(ref.read(desktopApiClientProvider));
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopLanState(status: state.status, error: error);
      }
      return error;
    }
  }
}

final desktopLanProvider = NotifierProvider<DesktopLanNotifier, DesktopLanState>(
  DesktopLanNotifier.new,
);
