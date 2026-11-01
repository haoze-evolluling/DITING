/// The rewrite page's data: the engine switch and default TTL, the rule list, and the four writes
/// (toggle, TTL, save one rule, delete one rule).
///
/// Every write re-reads what the service kept instead of writing the expected result into the
/// page, because the service validates domains, records and response codes and its answer is the
/// only truth.
library;

import 'dart:async';

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_rewrite_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopRewriteState {
  const DesktopRewriteState({this.config, this.error, this.saving = false});

  final DesktopRewriteConfig? config;

  /// The last read failed. The previous config stays on screen so the page can say "these are the
  /// values from before" instead of blanking. A rejected write is not kept here: the caller already
  /// has the service's reason and shows it, and the write never changed what the service holds.
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

  /// One write at a time, then a full re-read. The rule list is part of the same state, so an edit
  /// and a toggle cannot interleave into a page that shows half of each.
  ///
  /// A rejection is returned to the caller and leaves the state alone: the service still has the old
  /// value, and the page is already showing it.
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
