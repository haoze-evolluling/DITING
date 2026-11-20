library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_rewrite_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopRewriteState {
  const DesktopRewriteState({this.config, this.error, this.saving = false});

  final DesktopRewriteConfig? config;

  final DesktopApiException? error;

  final bool saving;

  bool get isLoading => config == null && error == null;
}

class DesktopRewriteNotifier extends Notifier<DesktopRewriteState> {
  @override
  DesktopRewriteState build() {
    unawaited(_load());
    return const DesktopRewriteState();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final config = await ref.read(desktopApiClientProvider).rewriteConfig();
      if (ref.mounted) state = DesktopRewriteState(config: config);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopRewriteState(config: state.config, error: error);
      }
    }
  }

  Future<DesktopApiException?> setEnabled(bool enabled) =>
      _write((client) => client.setRewriteEnabled(enabled));

  Future<DesktopApiException?> setTtl(int ttl) =>
      _write((client) => client.setRewriteTtl(ttl));

  Future<DesktopApiException?> saveRule(DesktopRewriteRule rule) =>
      _write((client) => client.saveRewriteRule(rule));

  Future<DesktopApiException?> deleteRule(String domain) =>
      _write((client) => client.deleteRewriteRule(domain));

  Future<DesktopApiException?> _write(
    Future<void> Function(DesktopApiClient client) body,
  ) async {
    if (state.saving) return null;
    state = DesktopRewriteState(config: state.config, saving: true);
    final client = ref.read(desktopApiClientProvider);
    try {
      await body(client);
      final config = await client.rewriteConfig();
      if (ref.mounted) state = DesktopRewriteState(config: config);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopRewriteState(config: state.config);
      }
      return error;
    }
  }
}

final desktopRewriteProvider =
    NotifierProvider<DesktopRewriteNotifier, DesktopRewriteState>(
      DesktopRewriteNotifier.new,
    );
