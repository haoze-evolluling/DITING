/// Safe search and the reputation lookups: their reads and their merge-style writes.
///
/// Both endpoints answer with the resulting state (safe browsing answers with config + counters), so
/// a write adopts that answer; the safe-search endpoint answers with a success flag only, so it is
/// re-read.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopSafeSearchState {
  const DesktopSafeSearchState({
    this.config,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopSafeSearchConfig? config;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;
}

class DesktopSafeSearchNotifier extends Notifier<DesktopSafeSearchState> {
  @override
  DesktopSafeSearchState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopSafeSearchState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final config = await client.safeSearch();
      if (ref.mounted) state = DesktopSafeSearchState(config: config);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopSafeSearchState(config: state.config, error: error);
      }
    }
  }

  Future<DesktopApiException?> save(Map<String, Object?> patch) async {
    if (state.saving) return null;
    state = DesktopSafeSearchState(config: state.config, saving: true);
    try {
      await ref.read(desktopApiClientProvider).configureSafeSearch(patch);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopSafeSearchState(config: state.config, error: error);
      }
      return error;
    }
    await _load(ref.read(desktopApiClientProvider));
    return null;
  }
}

final desktopSafeSearchProvider =
    NotifierProvider<DesktopSafeSearchNotifier, DesktopSafeSearchState>(
      DesktopSafeSearchNotifier.new,
    );

class DesktopReputationState {
  const DesktopReputationState({
    this.data,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopSafeBrowsing? data;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;
}

class DesktopReputationNotifier extends Notifier<DesktopReputationState> {
  @override
  DesktopReputationState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopReputationState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final data = await client.safeBrowsing();
      if (ref.mounted) state = DesktopReputationState(data: data);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopReputationState(data: state.data, error: error);
      }
    }
  }

  /// The service answers with the normalised state, which the page adopts directly.
  Future<DesktopApiException?> save(Map<String, Object?> patch) async {
    if (state.saving) return null;
    state = DesktopReputationState(data: state.data, saving: true);
    try {
      final data = await ref
          .read(desktopApiClientProvider)
          .configureSafeBrowsing(patch);
      if (ref.mounted) state = DesktopReputationState(data: data);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopReputationState(data: state.data, error: error);
      }
      return error;
    }
  }
}

final desktopReputationProvider =
    NotifierProvider<DesktopReputationNotifier, DesktopReputationState>(
      DesktopReputationNotifier.new,
    );
