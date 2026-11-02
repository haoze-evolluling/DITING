/// The local authoritative zones' data: the config, the service's per-zone build results, and the
/// three writes (engine switch, default TTL, the whole zone list).
///
/// A zone that fails to parse is an expected answer rather than an outage, so only a failed request
/// becomes [DesktopZoneConfigState.error]; the per-zone reasons come from the service's own states.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_zone_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopZoneConfigState {
  const DesktopZoneConfigState({this.config, this.error, this.saving = false});

  final DesktopZoneConfig? config;

  /// The last read failed. The previous config stays on screen so the card can say the figures are
  /// from before; a rejected write is returned to the caller instead.
  final DesktopApiException? error;

  final bool saving;
}

class DesktopZoneNotifier extends Notifier<DesktopZoneConfigState> {
  @override
  DesktopZoneConfigState build() {
    unawaited(_load());
    return const DesktopZoneConfigState();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final config = await ref.read(desktopApiClientProvider).zoneConfig();
      if (ref.mounted) state = DesktopZoneConfigState(config: config);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopZoneConfigState(config: state.config, error: error);
      }
    }
  }

  Future<DesktopApiException?> setEnabled(bool enabled) =>
      _write((client) => client.updateZoneConfig(enabled: enabled));

  Future<DesktopApiException?> setTtl(int ttl) =>
      _write((client) => client.updateZoneConfig(ttl: ttl));

  Future<DesktopApiException?> saveZones(List<DesktopZoneEntry> zones) =>
      _write((client) => client.updateZoneConfig(zones: zones));

  /// One write at a time. The service answers with the rebuilt state of every zone, so the card can
  /// show which zone it rejected instead of only a message.
  Future<DesktopApiException?> _write(
    Future<DesktopZoneConfig?> Function(DesktopApiClient client) body,
  ) async {
    if (state.saving) return null;
    state = DesktopZoneConfigState(config: state.config, saving: true);
    final client = ref.read(desktopApiClientProvider);
    try {
      final applied = await body(client) ?? await client.zoneConfig();
      if (ref.mounted) state = DesktopZoneConfigState(config: applied);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) state = DesktopZoneConfigState(config: state.config);
      return error;
    }
  }
}

final desktopZoneProvider =
    NotifierProvider<DesktopZoneNotifier, DesktopZoneConfigState>(
      DesktopZoneNotifier.new,
    );
