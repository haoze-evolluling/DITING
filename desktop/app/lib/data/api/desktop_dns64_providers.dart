library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_dns64_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopDns64State {
  const DesktopDns64State({
    this.config,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopDns64Config? config;

  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => config != null && error != null;
}

class DesktopDns64Notifier extends Notifier<DesktopDns64State> {
  @override
  DesktopDns64State build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopDns64State(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final config = await client.dns64Config();
      if (ref.mounted) state = DesktopDns64State(config: config);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopDns64State(config: state.config, error: error);
      }
    }
  }

  Future<DesktopApiException?> save(DesktopDns64Config next) async {
    if (state.saving) return null;
    state = DesktopDns64State(config: state.config, saving: true);
    try {
      await ref.read(desktopApiClientProvider).updateDns64Config(next);
      final config = await ref.read(desktopApiClientProvider).dns64Config();
      if (ref.mounted) state = DesktopDns64State(config: config);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopDns64State(config: state.config, error: error);
      }
      return error;
    }
  }
}

final desktopDns64Provider =
    NotifierProvider<DesktopDns64Notifier, DesktopDns64State>(
      DesktopDns64Notifier.new,
    );
