library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_schedule_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopScheduleState {
  const DesktopScheduleState({
    this.config,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopScheduleConfig? config;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => config != null && error != null;
}

class DesktopScheduleNotifier extends Notifier<DesktopScheduleState> {
  @override
  DesktopScheduleState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopScheduleState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final config = await client.blockingSchedule();
      if (ref.mounted) state = DesktopScheduleState(config: config);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopScheduleState(config: state.config, error: error);
      }
    }
  }

  Future<DesktopApiException?> save(DesktopScheduleConfig next) async {
    if (state.saving) return null;
    state = DesktopScheduleState(config: state.config, saving: true);
    try {
      await ref.read(desktopApiClientProvider).updateBlockingSchedule(next);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopScheduleState(config: state.config, error: error);
      }
      return error;
    }
    await _load(ref.read(desktopApiClientProvider));
    return null;
  }
}

final desktopScheduleProvider =
    NotifierProvider<DesktopScheduleNotifier, DesktopScheduleState>(
      DesktopScheduleNotifier.new,
    );
