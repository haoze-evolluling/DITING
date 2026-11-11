/// Server-mode resolution state: the scheduling mode plus the candidate set its race modes use.
///
/// The values live in the server data set (`diting_dns_mode_prefs`), alongside
/// `selected_upstream_id` and `custom_upstreams`; `LegacySettings.forServer()` keeps reads and
/// writes on that container even when the caller holds a differently-scoped settings view.
library;

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/server_upstream_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ServerResolutionModeNotifier extends Notifier<ResolutionMode> {
  @override
  ResolutionMode build() {
    ref.watch(legacySettingsProvider);
    return ResolutionMode.fromStorageValue(
      ref.read(legacySettingsProvider).forServer().resolutionModeRaw,
    );
  }

  void select(ResolutionMode mode) {
    state = mode;
    ref
        .read(legacySettingsProvider)
        .forServer()
        .setResolutionModeRaw(mode.storageValue);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

final serverResolutionModeProvider =
    NotifierProvider<ServerResolutionModeNotifier, ResolutionMode>(
      ServerResolutionModeNotifier.new,
    );

/// Candidate upstreams for the server race modes, mirroring the tunnel's `RaceProvidersNotifier`
/// against the server catalog instead of the normal-mode provider catalog.
class ServerRaceProvidersNotifier extends Notifier<Set<String>> {
  static const minCount = 2;

  @override
  Set<String> build() {
    final settings = ref.watch(legacySettingsProvider).forServer();
    final mode = ref.watch(serverResolutionModeProvider);
    final catalogIds = {
      for (final upstream in ref.watch(serverUpstreamListProvider)) upstream.id,
    };
    final stored = mode.isSingle
        ? settings.parallelRaceProviderIds
        : settings.providerIdsOf(mode.storageValue);
    final storedOrDefault = stored.isEmpty && mode.isSingle
        ? const ['preset_alidns_dns', 'preset_dnspod_dns']
        : stored;
    return {
      for (final id in storedOrDefault)
        if (catalogIds.contains(id)) id,
    };
  }

  /// Returns false when the removal would drop below [minCount].
  bool toggle(String id) {
    final catalogIds = {
      for (final upstream in ref.read(serverUpstreamListProvider)) upstream.id,
    };
    if (!catalogIds.contains(id)) {
      return false;
    }
    final next = {...state};
    final removing = next.remove(id);
    if (removing && next.length < minCount) {
      return false;
    }
    if (!removing) {
      next.add(id);
    }
    _persist(next);
    state = next;
    return true;
  }

  void reset() {
    final defaults = {
      for (final upstream in ref.read(serverUpstreamListProvider).take(2))
        upstream.id,
    };
    _persist(defaults);
    state = defaults;
  }

  /// Persists an explicit order; primary-backup keeps the sequence, the modes are sets.
  void reorder(List<String> ids) {
    final valid = {
      for (final upstream in ref.read(serverUpstreamListProvider)) upstream.id,
    };
    final ordered = [
      for (final id in ids)
        if (valid.contains(id)) id,
    ];
    final settings = ref.read(legacySettingsProvider).forServer();
    final mode = ref.read(serverResolutionModeProvider);
    if (mode.isSingle) {
      settings.setParallelRaceProviderIds(ordered);
    } else {
      settings.setProviderIdsOf(mode.storageValue, ordered);
    }
    state = ordered.toSet();
  }

  void _persist(Set<String> ids) {
    final settings = ref.read(legacySettingsProvider).forServer();
    final mode = ref.read(serverResolutionModeProvider);
    if (mode.isSingle) {
      settings.setParallelRaceProviderIds(ids.toList());
      return;
    }
    final key = mode.storageValue;
    if (key == 'primary_backup') {
      // Preserve the primary-to-backup order; newly added ids go last.
      final current = settings.providerIdsOf(key);
      final ordered = [
        for (final id in current)
          if (ids.contains(id)) id,
        for (final id in ids)
          if (!current.contains(id)) id,
      ];
      settings.setProviderIdsOf(key, ordered);
      return;
    }
    settings.setProviderIdsOf(key, ids.toList());
  }
}

final serverRaceProvidersProvider =
    NotifierProvider<ServerRaceProvidersNotifier, Set<String>>(
      ServerRaceProvidersNotifier.new,
    );
