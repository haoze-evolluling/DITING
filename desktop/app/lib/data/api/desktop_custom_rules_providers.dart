library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopCustomRulesState {
  const DesktopCustomRulesState({
    this.rules = const [],
    this.error,
    this.isLoading = false,
    this.saving = false,
    this.loaded = false,
  });

  final List<String> rules;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  final bool loaded;

  bool get isStale => loaded && error != null;
}

class DesktopCustomRulesNotifier extends Notifier<DesktopCustomRulesState> {
  @override
  DesktopCustomRulesState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopCustomRulesState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final rules = await client.customRules();
      if (ref.mounted) {
        state = DesktopCustomRulesState(rules: rules, loaded: true);
      }
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopCustomRulesState(
          rules: state.rules,
          loaded: state.loaded,
          error: error,
        );
      }
    }
  }

  Future<DesktopApiException?> save(List<String> rules) async {
    if (state.saving) return null;
    state = DesktopCustomRulesState(
      rules: state.rules,
      loaded: state.loaded,
      saving: true,
    );
    try {
      await ref.read(desktopApiClientProvider).setCustomRules(rules);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopCustomRulesState(
          rules: state.rules,
          loaded: state.loaded,
          error: error,
        );
      }
      return error;
    }
    await _load(ref.read(desktopApiClientProvider));
    return null;
  }
}

final desktopCustomRulesProvider =
    NotifierProvider<DesktopCustomRulesNotifier, DesktopCustomRulesState>(
      DesktopCustomRulesNotifier.new,
    );
