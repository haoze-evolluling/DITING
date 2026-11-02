/// The protection pages' engine config and pause state.
///
/// Both reads come from the service; every write re-reads what it kept. The config form is posted as
/// a whole subset (the service merges it), so a rejected save leaves the previous values on screen.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_filter_config_models.dart';
import 'package:diting_desktop/data/api/desktop_filter_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopFilterConfigState {
  const DesktopFilterConfigState({
    this.config,
    this.summary,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopFilterConfig? config;
  final DesktopFilterSummary? summary;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => config != null && error != null;
}

class DesktopFilterConfigNotifier extends Notifier<DesktopFilterConfigState> {
  @override
  DesktopFilterConfigState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopFilterConfigState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final summary = await client.filterStats();
      final config = await client.filterConfig();
      if (ref.mounted) {
        state = DesktopFilterConfigState(config: config, summary: summary);
      }
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopFilterConfigState(
          config: state.config,
          summary: state.summary,
          error: error,
        );
      }
    }
  }

  /// Saves the form. Returns the failure for the page's snackbar; on success both the config and the
  /// counters are re-read, because a switch changes the numbers above it too.
  Future<DesktopApiException?> save(DesktopFilterConfig next) async {
    if (state.saving) return null;
    state = DesktopFilterConfigState(
      config: state.config,
      summary: state.summary,
      saving: true,
    );
    try {
      await ref.read(desktopApiClientProvider).updateFilterConfig(next);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopFilterConfigState(
          config: state.config,
          summary: state.summary,
          error: error,
        );
      }
      return error;
    }
    await _load(ref.read(desktopApiClientProvider));
    return null;
  }
}

final desktopFilterConfigProvider =
    NotifierProvider<DesktopFilterConfigNotifier, DesktopFilterConfigState>(
      DesktopFilterConfigNotifier.new,
    );

class DesktopFilterPauseState {
  const DesktopFilterPauseState({
    this.pause = DesktopFilterPause.idle,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopFilterPause pause;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;
}

class DesktopFilterPauseNotifier extends Notifier<DesktopFilterPauseState> {
  @override
  DesktopFilterPauseState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopFilterPauseState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final pause = await client.filterPause();
      if (ref.mounted) state = DesktopFilterPauseState(pause: pause);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopFilterPauseState(pause: state.pause, error: error);
      }
    }
  }

  /// Pauses for [durationSec] (0 means until resumed by hand), or resumes immediately.
  Future<DesktopApiException?> setPaused(
    bool paused, {
    int durationSec = 0,
  }) async {
    if (state.saving) return null;
    state = DesktopFilterPauseState(pause: state.pause, saving: true);
    try {
      await ref
          .read(desktopApiClientProvider)
          .setFilterPaused(paused, durationSec: paused ? durationSec : null);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopFilterPauseState(pause: state.pause, error: error);
      }
      return error;
    }
    await _load(ref.read(desktopApiClientProvider));
    return null;
  }
}

final desktopFilterPauseProvider =
    NotifierProvider<DesktopFilterPauseNotifier, DesktopFilterPauseState>(
      DesktopFilterPauseNotifier.new,
    );
