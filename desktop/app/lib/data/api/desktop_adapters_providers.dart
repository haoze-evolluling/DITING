/// The adapter takeover page's state and its three writes.
///
/// `/adapters` carries the adapter list, `/status` carries which of them are taken over; the page
/// needs both, so one notifier reads both and re-reads both after every write. A rejected write keeps
/// the last state and returns the reason instead of guessing what happened.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_adapters_models.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopAdaptersState {
  const DesktopAdaptersState({
    this.adapters = const [],
    this.takeoverActive = false,
    this.takenOver = const {},
    this.isLoading = false,
    this.saving = false,
    this.error,
  });

  final List<DesktopAdapter> adapters;

  /// Whether the service reports any takeover at all; the summary card's action depends on it.
  final bool takeoverActive;

  /// Adapter ids and names the service says it is taking over, as `/status` reports both.
  final Set<String> takenOver;
  final bool isLoading;
  final bool saving;
  final DesktopApiException? error;

  bool get isStale => adapters.isNotEmpty && error != null;

  bool isTakenOver(DesktopAdapter adapter) =>
      takenOver.contains(adapter.id) || takenOver.contains(adapter.name);
}

class DesktopAdaptersNotifier extends Notifier<DesktopAdaptersState> {
  @override
  DesktopAdaptersState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopAdaptersState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final adapters = await client.adapters();
      final status = await client.status();
      if (!ref.mounted) return;
      state = DesktopAdaptersState(
        adapters: adapters,
        takeoverActive: status.takeover.active,
        takenOver: status.takeover.adapters.toSet(),
      );
    } on DesktopApiException catch (error) {
      if (!ref.mounted) return;
      state = DesktopAdaptersState(
        adapters: state.adapters,
        takeoverActive: state.takeoverActive,
        takenOver: state.takenOver,
        error: error,
      );
    }
  }

  /// Takes one adapter over (or restores it). The switch on the card calls this.
  Future<DesktopApiException?> setAdapter(String adapterId, bool enable) =>
      _write(() async {
        await ref
            .read(desktopApiClientProvider)
            .setAdapterTakeover(adapterId, enable);
      });

  /// `POST /takeover/enable|disable`: every physical adapter at once.
  Future<DesktopApiException?> setAll(bool enable) => _write(() async {
    await ref.read(desktopApiClientProvider).setTakeover(enable);
  });

  Future<DesktopApiException?> _write(Future<void> Function() write) async {
    if (state.saving) return null;
    state = DesktopAdaptersState(
      adapters: state.adapters,
      takeoverActive: state.takeoverActive,
      takenOver: state.takenOver,
      saving: true,
    );
    try {
      await write();
      await _load(ref.read(desktopApiClientProvider));
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopAdaptersState(
          adapters: state.adapters,
          takeoverActive: state.takeoverActive,
          takenOver: state.takenOver,
          error: error,
        );
      }
      return error;
    }
  }
}

final desktopAdaptersProvider =
    NotifierProvider<DesktopAdaptersNotifier, DesktopAdaptersState>(
      DesktopAdaptersNotifier.new,
    );
