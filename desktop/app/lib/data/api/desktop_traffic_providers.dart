/// The recognised clients and their limits.
///
/// Every write answers with a success flag only, so each one re-reads the state it touched: an alias
/// save reloads the client list, a limit save reloads `/status`. A rejected write keeps what was on
/// screen and returns the service's reason.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_traffic_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopTrafficState {
  const DesktopTrafficState({
    this.clients = const [],
    this.limits,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final List<DesktopClient> clients;
  final DesktopClientLimits? limits;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => limits != null && error != null;
}

class DesktopTrafficNotifier extends Notifier<DesktopTrafficState> {
  @override
  DesktopTrafficState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopTrafficState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final results = await Future.wait([
        client.clients(),
        client.clientLimits(),
      ]);
      if (!ref.mounted) return;
      state = DesktopTrafficState(
        clients: results[0] as List<DesktopClient>,
        limits: results[1] as DesktopClientLimits,
      );
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopTrafficState(
          clients: state.clients,
          limits: state.limits,
          error: error,
        );
      }
    }
  }

  /// An empty name clears the alias, which is how the old console's dialog behaved.
  Future<DesktopApiException?> setAlias(String ip, String name) async {
    try {
      await ref
          .read(desktopApiClientProvider)
          .configureClientAlias(ip: ip, name: name);
      await reload();
      return null;
    } on DesktopApiException catch (error) {
      return error;
    }
  }

  Future<DesktopApiException?> saveAccess(
    DesktopAccessControl access,
  ) => _write(() async {
    await ref
        .read(desktopApiClientProvider)
        .configureAccess(
          allowedClients: access.allowed,
          blockedClients: access.blocked,
        );
  });

  Future<DesktopApiException?> saveRateLimit(DesktopRateLimit rateLimit) =>
      _write(() async {
        await ref
            .read(desktopApiClientProvider)
            .configureRateLimit(rateLimit.toJson());
      });

  Future<DesktopApiException?> _write(Future<void> Function() write) async {
    if (state.saving) return null;
    state = DesktopTrafficState(
      clients: state.clients,
      limits: state.limits,
      saving: true,
    );
    try {
      await write();
      await _load(ref.read(desktopApiClientProvider));
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopTrafficState(
          clients: state.clients,
          limits: state.limits,
          error: error,
        );
      }
      return error;
    }
  }
}

final desktopTrafficProvider =
    NotifierProvider<DesktopTrafficNotifier, DesktopTrafficState>(
      DesktopTrafficNotifier.new,
    );
