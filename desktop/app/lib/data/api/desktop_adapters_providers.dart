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

  final bool takeoverActive;

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

  Future<DesktopApiException?> setAdapter(String adapterId, bool enable) =>
      _write(() async {
        await ref
            .read(desktopApiClientProvider)
            .setAdapterTakeover(adapterId, enable);
      });

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
