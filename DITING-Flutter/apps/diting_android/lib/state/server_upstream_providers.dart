import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/server/dns_server_config.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Server mode's upstream list: 18 presets plus legacy custom entries, watching
/// `legacySettingsProvider`.
final serverUpstreamListProvider = Provider<List<ServerUpstream>>((ref) {
  return serverUpstreams(ref.watch(legacySettingsProvider));
});

class ServerSelectedUpstreamNotifier extends Notifier<ServerUpstream> {
  @override
  ServerUpstream build() {
    final settings = ref.watch(legacySettingsProvider);
    final upstreams = serverUpstreams(settings);
    return upstreams.firstWhere(
      (upstream) => upstream.id == settings.serverSelectedUpstreamId,
      orElse: () => upstreams.first,
    );
  }

  void select(String id) {
    final match = ref
        .read(serverUpstreamListProvider)
        .where((upstream) => upstream.id == id);
    if (match.isEmpty) return;
    state = match.first;
    ref.read(legacySettingsProvider).setServerSelectedUpstreamId(id);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

final serverSelectedUpstreamProvider =
    NotifierProvider<ServerSelectedUpstreamNotifier, ServerUpstream>(
      ServerSelectedUpstreamNotifier.new,
    );

/// Legacy rules: `custom_` ids, IPv6 brackets dropped, and a deleted selection falls back to the
/// first preset.
class ServerUpstreamActions {
  ServerUpstreamActions(this._ref);

  final Ref _ref;

  /// Adds an entry; returns null on invalid input so the dialog stays open.
  ServerUpstream? add({
    required String name,
    required DnsProtocol protocol,
    required String address,
    required int port,
  }) {
    final validation = validateServerUpstream(
      name: name,
      protocol: protocol,
      address: address,
      port: port,
    );
    if (validation is UpstreamInvalid) {
      return null;
    }
    final server = ServerUpstream(
      id: _newCustomId(),
      name: name.trim(),
      protocol: protocol,
      address: normalizeServerUpstreamAddress(protocol, address),
      port: port,
    );
    _write([..._custom(), server]);
    return server;
  }

  /// Edits an entry; `id` must be an existing custom entry, presets are read-only.
  bool update(ServerUpstream server) {
    if (!_isCustom(server.id)) {
      return false;
    }
    final validation = validateServerUpstream(
      name: server.name,
      protocol: server.protocol,
      address: server.address,
      port: server.port,
    );
    if (validation is UpstreamInvalid) {
      return false;
    }
    final normalized = ServerUpstream(
      id: server.id,
      name: server.name.trim(),
      protocol: server.protocol,
      address: normalizeServerUpstreamAddress(server.protocol, server.address),
      port: server.port,
    );
    _write([
      for (final existing in _custom())
        if (existing.id == normalized.id) normalized else existing,
    ]);
    return true;
  }

  /// Deletes an entry, falling back to the first preset when it was selected.
  bool remove(String id) {
    if (!_isCustom(id)) {
      return false;
    }
    _write([
      for (final existing in _custom())
        if (existing.id != id) existing,
    ]);
    final settings = _ref.read(legacySettingsProvider);
    if (settings.serverSelectedUpstreamId == id) {
      settings.setServerSelectedUpstreamId(
        serverPresetUpstreams(currentL10n).first.id,
      );
      _ref.read(legacySettingsRevisionProvider.notifier).bump();
    }
    return true;
  }

  List<ServerUpstream> _custom() => parseServerCustomUpstreams(
    _ref.read(legacySettingsProvider).serverCustomUpstreamsJson,
  );

  void _write(List<ServerUpstream> servers) {
    _ref
        .read(legacySettingsProvider)
        .setServerCustomUpstreamsJson(encodeServerCustomUpstreams(servers));
    _ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  static bool _isCustom(String id) => !id.startsWith('preset_');

  /// `custom_` plus a timestamp and counter: unique per session without a UUID dependency.
  static int _seq = 0;
  static String _newCustomId() {
    _seq++;
    return 'custom_${DateTime.now().microsecondsSinceEpoch}_$_seq';
  }
}

final serverUpstreamActionsProvider = Provider<ServerUpstreamActions>(
  ServerUpstreamActions.new,
);
