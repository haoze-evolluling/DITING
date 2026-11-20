library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_upstream_models.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopUpstreamState {
  const DesktopUpstreamState({
    this.config,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopUpstreamConfig? config;

  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => config != null && error != null;
}

class DesktopUpstreamNotifier extends Notifier<DesktopUpstreamState> {
  @override
  DesktopUpstreamState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopUpstreamState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final config = await client.upstreamConfig();
      if (ref.mounted) {
        state = DesktopUpstreamState(config: config);
      }
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopUpstreamState(config: state.config, error: error);
      }
    }
  }

  Future<DesktopApiException?> save(DesktopUpstreamConfig next) async {
    if (state.saving) return null;
    state = DesktopUpstreamState(config: state.config, saving: true);
    try {
      await ref.read(desktopApiClientProvider).updateUpstreamConfig(next);
      final config = await ref.read(desktopApiClientProvider).upstreamConfig();
      if (ref.mounted) state = DesktopUpstreamState(config: config);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopUpstreamState(config: state.config, error: error);
      }
      return error;
    }
  }
}

final desktopUpstreamProvider =
    NotifierProvider<DesktopUpstreamNotifier, DesktopUpstreamState>(
      DesktopUpstreamNotifier.new,
    );

class DesktopUpstreamProbeState {
  const DesktopUpstreamProbeState({this.busyId, this.results = const {}});

  final String? busyId;

  final Map<String, DesktopUpstreamProbe> results;

  bool isBusy(String id) => busyId == id;
}

class DesktopUpstreamProbeNotifier extends Notifier<DesktopUpstreamProbeState> {
  @override
  DesktopUpstreamProbeState build() => const DesktopUpstreamProbeState();

  Future<DesktopUpstreamProbe> test(DesktopUpstreamProvider provider) async {
    if (state.busyId != null) return const DesktopUpstreamProbe();
    state = DesktopUpstreamProbeState(
      busyId: provider.id,
      results: state.results,
    );
    DesktopUpstreamProbe result;
    try {
      result = await ref
          .read(desktopApiClientProvider)
          .testUpstream(
            protocol: provider.protocol,
            server: provider.server,
            url: provider.url,
          );
    } on DesktopApiException catch (error) {
      result = DesktopUpstreamProbe(error: error.message);
    }
    if (ref.mounted) {
      state = DesktopUpstreamProbeState(
        results: {...state.results, provider.id: result},
      );
    }
    return result;
  }
}

final desktopUpstreamProbeProvider =
    NotifierProvider<
      DesktopUpstreamProbeNotifier,
      DesktopUpstreamProbeState
    >(DesktopUpstreamProbeNotifier.new);
