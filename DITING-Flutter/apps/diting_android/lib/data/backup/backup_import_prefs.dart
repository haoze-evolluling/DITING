part of 'backup_importer.dart';

/// Merges the prefs-backed groups; never touches the rule database.
extension _BackupImportPrefs on BackupImporter {
  BackupGroupOutcome _importProviders(
    Object? value,
    BackupImportTarget target,
  ) {
    // Accept both the legacy array and the newer `{items, selection}` form.
    final List<Object?> incoming;
    if (value is List) {
      incoming = value;
    } else if (value is Map && value['items'] is List) {
      incoming = value['items'] as List<Object?>;
    } else {
      throw BackupFormatException(currentL10n.backupErrProvidersNotArray);
    }
    final existing = _decodeProviders(target.settings.userProvidersJson);
    final byName = {for (final item in existing) _nameOf(item): item};
    var added = 0;
    var updated = 0;
    var skipped = 0;
    for (final item in incoming) {
      if (item is! Map) {
        skipped++;
        continue;
      }
      final name = _nameOf(item);
      if (name.isEmpty) {
        skipped++;
        continue;
      }
      final normalized = _withId(item, name);
      final current = byName[name];
      if (current == null) {
        existing.add(normalized);
        byName[name] = normalized;
        added++;
      } else if (_encodeConfig(current) == _encodeConfig(normalized)) {
        skipped++;
      } else {
        final index = existing.indexOf(current);
        // Keep the local id: UI selections and candidate lists reference it.
        existing[index] = _keepId(normalized, current);
        byName[name] = existing[index];
        updated++;
      }
    }
    if (added > 0 || updated > 0) {
      target.store.putString(
        LegacySettings.uiContainer,
        'user_providers_json',
        jsonEncode(existing),
      );
    }
    return BackupGroupOutcome(
      group: BackupGroup.providers,
      added: added,
      skipped: skipped,
      updated: updated,
    );
  }

  /// Fill in a missing id from the name so re-imports stay idempotent.
  Map<Object?, Object?> _withId(Map<Object?, Object?> provider, String name) {
    final id = provider['id'];
    if (id is String && id.trim().isNotEmpty) return provider;
    return {...provider, 'id': 'user_${_slugOf(name)}'};
  }

  Map<Object?, Object?> _keepId(
    Map<Object?, Object?> incoming,
    Map<Object?, Object?> current,
  ) {
    final id = current['id'];
    if (id is String && id.isNotEmpty) return {...incoming, 'id': id};
    return incoming;
  }

  String _slugOf(String value) {
    final buffer = StringBuffer();
    for (final unit in value.trim().toLowerCase().codeUnits) {
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isLower = unit >= 0x61 && unit <= 0x7a;
      buffer.write(isDigit || isLower ? String.fromCharCode(unit) : '_');
    }
    return buffer.isEmpty ? 'provider' : buffer.toString();
  }

  List<Map<Object?, Object?>> _decodeProviders(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map) Map<Object?, Object?>.from(item),
      ];
    } on FormatException {
      return [];
    }
  }

  String _nameOf(Map<Object?, Object?> provider) {
    final name = provider['name'];
    return name is String ? name.trim() : '';
  }

  /// Content only: ids are generated locally, so comparing them would mark every re-import as an
  /// update that never clears.
  String _encodeConfig(Object? value) {
    if (value is Map) {
      final stripped = {
        for (final entry in value.entries)
          if ('${entry.key}' != 'id') entry.key: entry.value,
      };
      return _encode(stripped);
    }
    return _encode(value);
  }

  String _encode(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return '{${keys.map((key) => '$key:${_encode(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_encode).join(',')}]';
    }
    return '$value';
  }

  void _applyProviderSelection(Object? value, BackupImportTarget target) {
    if (value is! Map) return;
    final settings = target.settings;
    final catalog = _providerNameIndex(settings);

    final selected = value['selectedProvider'];
    if (selected is Map) {
      final id = _resolveProviderId(selected, catalog);
      if (id != null) settings.setSelectedProviderId(id);
    }

    final mode = value['resolutionMode'];
    if (mode is String && mode.isNotEmpty) settings.setResolutionModeRaw(mode);

    final raceDomain = value['raceTestDomain'];
    if (raceDomain is String && raceDomain.trim().isNotEmpty) {
      settings.setRaceTestDomain(raceDomain.trim());
    }

    _applyProviderIds(
      settings,
      value['raceProviderRefs'],
      catalog,
      settings.setRaceProviderIds,
    );
    _applyProviderIds(
      settings,
      value['smartPredictionProviderRefs'],
      catalog,
      settings.setSmartPredictionProviderIds,
    );
    _applyProviderIds(
      settings,
      value['parallelRaceProviderRefs'],
      catalog,
      settings.setParallelRaceProviderIds,
    );
    _applyProviderIds(
      settings,
      value['primaryBackupProviderRefs'],
      catalog,
      settings.setPrimaryBackupProviderIds,
    );
    _applyProviderIds(
      settings,
      value['latencyTestProviderRefs'],
      catalog,
      settings.setLatencyTestProviderIds,
    );

    final visibility = value['homeProviderVisibility'];
    if (visibility is Map) {
      final protocols = _stringSet(visibility['visibleProtocols']);
      settings.setHomeProviderVisibility(
        visibleProtocols: protocols.isEmpty
            ? settings.homeVisibleProtocols
            : protocols,
        hiddenProviderIds: _idsOf(visibility['hiddenProviderRefs'], catalog),
        visibleProviderIds: _idsOf(visibility['visibleProviderRefs'], catalog),
      );
    }
  }

  void _applyProviderIds(
    LegacySettings settings,
    Object? refs,
    Map<String, String> catalog,
    void Function(List<String> ids) write,
  ) {
    if (refs is! List) return;
    // An empty list is meaningful (the user may have cleared candidates).
    write(_idsOf(refs, catalog).toList());
  }

  Set<String> _idsOf(Object? refs, Map<String, String> catalog) {
    if (refs is! List) return const {};
    final ids = <String>{};
    for (final ref in refs) {
      if (ref is! Map) continue;
      final id = _resolveProviderId(ref, catalog);
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// Local id for a reference, else the (name, protocol) fallback of old backups whose ids no
  /// longer exist.
  String? _resolveProviderId(Map ref, Map<String, String> catalog) {
    final id = ref['id'];
    if (id is String && id.isNotEmpty && catalog.containsKey(id)) return id;
    final name = ref['name'];
    if (name is String && name.isNotEmpty) {
      final protocol = ref['protocol'];
      final key =
          '$name\u0000${protocol is String ? protocol.toUpperCase() : ''}';
      return catalog[key];
    }
    return id is String && id.isNotEmpty ? id : null;
  }

  Map<String, String> _providerNameIndex(LegacySettings settings) {
    final index = <String, String>{};
    void add(String id, String name, String protocol) {
      index[id] = id;
      index['$name\u0000${protocol.toUpperCase()}'] = id;
    }

    for (final provider in defaultDnsProviders(currentL10n)) {
      add(provider.id, provider.name, provider.protocol.storageValue);
    }
    for (final record in readUserProviders(settings)) {
      add(record.id, record.name, record.protocol.storageValue);
    }
    return index;
  }

  BackupGroupOutcome _importBootstrap(
    Object? value,
    BackupImportTarget target,
  ) {
    if (value is! Map) {
      throw BackupFormatException(currentL10n.backupErrBootstrapNotObject);
    }
    final settings = target.settings;
    var added = 0;
    var skipped = 0;

    final enabled = value['enabled'];
    if (enabled is bool) {
      if (settings.bootstrapEnabled == enabled) {
        skipped++;
      } else {
        settings.setBootstrapEnabled(enabled);
        added++;
      }
    } else {
      skipped++;
    }

    final presetIds = value['presetIds'];
    if (presetIds is List) {
      final ids = {
        for (final id in presetIds)
          if (id is String) id,
      };
      if (ids.length == settings.bootstrapPresetIds.length &&
          ids.containsAll(settings.bootstrapPresetIds)) {
        skipped++;
      } else {
        settings.setBootstrapPresetIds(ids);
        added++;
      }
    } else {
      skipped++;
    }

    final custom = value['custom'];
    if (custom != null) {
      // This entry is the raw custom node text, so write back the encoded JSON.
      final encoded = jsonEncode(custom);
      if (settings.bootstrapCustomJson == encoded) {
        skipped++;
      } else {
        settings.setBootstrapCustomJson(encoded);
        added++;
      }
    } else {
      skipped++;
    }

    return BackupGroupOutcome(
      group: BackupGroup.bootstrap,
      added: added,
      skipped: skipped,
    );
  }

  /// Written through `applyCachePreset` so the engine never sees a new mode with an old TTL.
  BackupGroupOutcome _importCache(Object? value, BackupImportTarget target) {
    if (value is! Map) {
      throw BackupFormatException(currentL10n.backupErrCacheNotObject);
    }
    final settings = target.settings;
    // Missing keys fall back to local values so all nine stay consistent.
    final enabled = value['enabled'];
    final mode = value['mode'];
    final preset = value['preset'];
    final maxTtl = value['maxTtlSeconds'];
    final fixedTtl = value['fixedTtlSeconds'];
    final minTtlEnabled = value['minTtlEnabled'];
    final minTtl = value['minTtlSeconds'];
    final staleEnabled = value['staleFallbackEnabled'];
    final staleSeconds = value['staleFallbackSeconds'];

    final next = (
      preset: preset is String ? preset : (settings.cachePresetRaw ?? ''),
      enabled: enabled is bool ? enabled : settings.cacheEnabled,
      mode: mode is String ? mode : settings.cacheModeRaw,
      maxTtl: maxTtl is int ? maxTtl : settings.cacheMaxTtlSeconds,
      fixedTtl: fixedTtl is int ? fixedTtl : settings.cacheFixedTtlSeconds,
      minTtlEnabled: minTtlEnabled is bool
          ? minTtlEnabled
          : settings.cacheMinTtlEnabled,
      minTtl: minTtl is int ? minTtl : settings.cacheMinTtlSeconds,
      staleEnabled: staleEnabled is bool
          ? staleEnabled
          : settings.cacheStaleFallbackEnabled,
      staleSeconds: staleSeconds is int
          ? staleSeconds
          : settings.cacheStaleFallbackSeconds,
    );
    final unchanged =
        next.preset == (settings.cachePresetRaw ?? '') &&
        next.enabled == settings.cacheEnabled &&
        next.mode == settings.cacheModeRaw &&
        next.maxTtl == settings.cacheMaxTtlSeconds &&
        next.fixedTtl == settings.cacheFixedTtlSeconds &&
        next.minTtlEnabled == settings.cacheMinTtlEnabled &&
        next.minTtl == settings.cacheMinTtlSeconds &&
        next.staleEnabled == settings.cacheStaleFallbackEnabled &&
        next.staleSeconds == settings.cacheStaleFallbackSeconds;
    if (unchanged) {
      return const BackupGroupOutcome(group: BackupGroup.cache, skipped: 1);
    }

    settings.applyCachePreset(
      storageValue: next.preset,
      enabled: next.enabled,
      mode: next.mode,
      maxTtlSeconds: next.maxTtl,
      fixedTtlSeconds: next.fixedTtl,
      minTtlEnabled: next.minTtlEnabled,
      minTtlSeconds: next.minTtl,
      staleFallbackEnabled: next.staleEnabled,
      staleFallbackSeconds: next.staleSeconds,
    );
    return const BackupGroupOutcome(
      group: BackupGroup.cache,
      // The nine keys are one policy; reporting 9 would look like nine rules.
      added: 1,
    );
  }

  /// Non-secret fields only and never auto-enabled: an on-switch without local credentials would
  /// fail to connect.
  BackupGroupOutcome _importOutbound(Object? value, BackupImportTarget target) {
    if (value is! Map) {
      throw BackupFormatException(currentL10n.backupErrOutboundNotObject);
    }
    var restored = 0;
    var skipped = 0;
    for (final entry in const {
      'protocol': 'outbound_proxy_protocol',
      'host': 'outbound_proxy_host',
      // An early 2.0 build wrote `outbound_proxy_app_package`, which always read empty.
      'proxyAppPackage': 'outbound_proxy_app',
    }.entries) {
      final raw = value[entry.key];
      if (raw is! String || raw.isEmpty) continue;
      final current = target.store.read(
        LegacySettings.uiContainer,
        entry.value,
      );
      if (current == raw) {
        skipped++;
        continue;
      }
      target.store.putString(LegacySettings.uiContainer, entry.value, raw);
      restored++;
    }
    final port = value['port'];
    if (port is int) {
      final current = target.store.read(
        LegacySettings.uiContainer,
        'outbound_proxy_port',
      );
      if (current == port) {
        skipped++;
      } else {
        target.store.putInt(
          LegacySettings.uiContainer,
          'outbound_proxy_port',
          port,
        );
        restored++;
      }
    }
    return BackupGroupOutcome(
      group: BackupGroup.outbound,
      // No credentials in backups, so "added" covers address fields only.
      added: restored,
      skipped: skipped,
    );
  }
}
