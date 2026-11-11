part of 'backup_exporter.dart';

// Snapshot of one export, keyed by group. The core reads exactly these fields; anything it needs and
// does not find is treated as "not set", never as an error.
//
// This is the only place that knows how the app stores a setting (getter names, defaults, which
// container), and the only place that touches SQLite. The user-row filter has to run in SQL: reading
// a subscription-sized table and dropping its rows here materialized every row in the ART heap,
// which is what once killed the process during an export (2026-10-31 log: heap climbed to
// 255MB/256MB and the last three seconds were GC-thrash). `*_source(source)` is indexed, so the join
// only touches user rows.

extension _BackupExportSnapshot on BackupExporter {
  Future<Map<String, Object?>> _snapshot(
    BackupExportSource source,
    Set<BackupGroup> selected,
  ) async {
    final fields = <String, Object?>{};
    // The rewrite table serves two groups; read it once per export.
    List<Map<String, Object?>>? rewriteRows;
    for (final group in BackupGroup.values) {
      if (!selected.contains(group)) continue;
      fields[group.key] = switch (group) {
        BackupGroup.providers => _providers(source),
        BackupGroup.bootstrap => _bootstrap(source),
        BackupGroup.cache => _cache(source),
        BackupGroup.outbound => _outbound(source),
        BackupGroup.subscriptions => await _subscriptions(source.database),
        BackupGroup.domainRules => await _domainRules(source.database),
        BackupGroup.rewriteDomain => {
          'rows': rewriteRows ??= await _userRuleRows(
            source.database,
            table: 'rewrite_rule',
            sourceTable: 'rewrite_rule_source',
          ),
        },
        BackupGroup.rewriteCname => {
          'rows': rewriteRows ??= await _userRuleRows(
            source.database,
            table: 'rewrite_rule',
            sourceTable: 'rewrite_rule_source',
          ),
        },
        BackupGroup.addressRules => {
          'rows': await _userRuleRows(
            source.database,
            table: 'go_url_rule',
            sourceTable: 'go_url_rule_source',
          ),
        },
        BackupGroup.excluded => {
          'packages': source.settings.excludedPackages.toList(),
        },
        BackupGroup.blocked => {
          'enabled': source.settings.blockedAppsEnabled,
          'packages': source.settings.blockedAppPackages.toList(),
        },
        BackupGroup.allowlist => {
          'enabled': source.settings.appAllowlistEnabled,
          'rules': {
            for (final entry in source.settings.appAllowlistRules.entries)
              entry.key: entry.value.toList(),
          },
        },
        BackupGroup.httpInspection => {
          'enabled': source.settings.httpInspectionEnabled,
          'http3Enabled': source.settings.http3InspectionEnabled,
          'packages': source.settings.httpInspectionPackages.toList(),
        },
        BackupGroup.appearance => _appearance(source),
        BackupGroup.system => _system(source),
      };
    }
    return fields;
  }

  Map<String, Object?> _providers(BackupExportSource source) {
    final settings = source.settings;
    return {
      'itemsJson': settings.userProvidersJson,
      // Presets first, then the user's own providers: the core resolves a reference by
      // `(name, protocol)` when the id it was written with no longer exists.
      'catalog': [
        for (final provider in defaultDnsProviders(currentL10n))
          {
            'id': provider.id,
            'name': provider.name,
            'protocol': provider.protocol.storageValue,
          },
        for (final record in readUserProviders(settings))
          {
            'id': record.id,
            'name': record.name,
            'protocol': record.protocol.storageValue,
          },
      ],
      'selectedProviderId': settings.selectedProviderId,
      'resolutionMode': settings.resolutionModeRaw,
      'presetDnsService': settings.presetDnsServiceRaw,
      'raceTestDomain': settings.raceTestDomain,
      'raceProviderIds': settings.raceProviderIds,
      'smartPredictionProviderIds': settings.smartPredictionProviderIds,
      'parallelRaceProviderIds': settings.parallelRaceProviderIds,
      'primaryBackupProviderIds': settings.primaryBackupProviderIds,
      'latencyTestProviderIds': settings.latencyTestProviderIds,
      'homeVisibleProtocols': settings.homeVisibleProtocols.toList(),
      'homeHiddenProviderIds': settings.homeHiddenProviderIds.toList(),
      'homeVisibleProviderIds': settings.homeVisibleProviderIds.toList(),
    };
  }

  Map<String, Object?> _bootstrap(BackupExportSource source) {
    final settings = source.settings;
    return {
      'enabled': settings.bootstrapEnabled,
      'presetIds': settings.bootstrapPresetIds,
      'customJson': settings.bootstrapCustomJson,
    };
  }

  Map<String, Object?> _cache(BackupExportSource source) {
    final settings = source.settings;
    return {
      'enabled': settings.cacheEnabled,
      'mode': settings.cacheModeRaw,
      'maxTtlSeconds': settings.cacheMaxTtlSeconds,
      'fixedTtlSeconds': settings.cacheFixedTtlSeconds,
      'minTtlEnabled': settings.cacheMinTtlEnabled,
      'minTtlSeconds': settings.cacheMinTtlSeconds,
      'staleFallbackEnabled': settings.cacheStaleFallbackEnabled,
      'staleFallbackSeconds': settings.cacheStaleFallbackSeconds,
      'preset': settings.cachePresetRaw,
    };
  }

  /// Protocol, host, port and target app only; no credentials.
  Map<String, Object?> _outbound(BackupExportSource source) {
    final settings = source.settings;
    return {
      'enabled': settings.rawValue('outbound_proxy_enabled') == true,
      'protocol': settings.rawValue('outbound_proxy_protocol'),
      'host': settings.rawValue('outbound_proxy_host'),
      'port': settings.rawValue('outbound_proxy_port'),
      'proxyAppPackage': settings.rawValue('outbound_proxy_app'),
    };
  }

  Future<Map<String, Object?>> _subscriptions(Database? db) async {
    if (db == null) return const {'groups': [], 'items': []};
    final repository = SubscriptionRepository(db);
    // `mirror_template` has no repository layer; early databases may lack the table.
    var templates = const <Map<String, Object?>>[];
    if (await _hasTable(db, 'mirror_template')) {
      templates = await db.query(
        'mirror_template',
        columns: ['name', 'template'],
        orderBy: 'name',
      );
    }
    return {
      'groups': [
        for (final group in await repository.groups())
          {
            'id': group.id,
            'name': group.name,
            'autoUpdateEnabled': group.autoUpdateEnabled,
          },
      ],
      'mirrorTemplates': templates,
      'items': [
        for (final row in await repository.all())
          {
            'url': row.url,
            'name': row.name,
            'kind': row.kind.storageValue,
            'sourceType': row.sourceType.storageValue,
            'enabled': row.enabled,
            'groupId': row.groupId,
            'mirrorTemplate': row.mirrorTemplate,
            'mirrorFallback': row.mirrorFallback,
          },
      ],
    };
  }

  Future<bool> _hasTable(Database db, String name) async {
    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, Object?>> _domainRules(Database? db) async => {
    'block': await _userRuleRows(
      db,
      table: 'block_rule',
      sourceTable: 'block_rule_source',
    ),
    'allow': await _userRuleRows(
      db,
      table: 'allow_rule',
      sourceTable: 'allow_rule_source',
    ),
  };

  /// User-origin rows of [table], filtered inside SQLite; a rule with several user sources appears
  /// once.
  Future<List<Map<String, Object?>>> _userRuleRows(
    Database? db, {
    required String table,
    required String sourceTable,
  }) async {
    if (db == null) return const [];
    return db.rawQuery(
      'SELECT r.* FROM $table r '
      'JOIN $sourceTable s ON s.ruleId = r.id '
      'WHERE s.source IN '
      '(${List.filled(RuleRepository.userSources.length, '?').join(',')}) '
      'GROUP BY r.id ORDER BY r.id DESC',
      RuleRepository.userSources,
    );
  }

  Map<String, Object?> _appearance(BackupExportSource source) {
    final settings = source.settings;
    final sentences = settings.homeSentences;
    return {
      'themeMode': settings.themeModeRaw,
      'palette': settings.paletteRaw,
      'liquidGlassMode': settings.liquidGlassModeRaw,
      'bottomBarStyle': settings.bottomBarStyleRaw,
      'tabTransition': settings.tabTransitionRaw,
      'componentOpacity': settings.componentOpacity,
      'hapticEnabled': settings.hapticEnabled,
      'bottomBarIds': settings.bottomBarIds,
      'customBackgroundEnabled': settings.customBackgroundEnabled,
      'homePowerButtonOpacity': settings.homeOpacity('home_power_button_opacity'),
      'homeProviderSelectorOpacity': settings.homeOpacity(
        'home_provider_selector_opacity',
      ),
      'homeModeButtonOpacity': settings.homeOpacity('home_mode_button_opacity'),
      'homePoemOpacity': settings.homeOpacity('home_poem_opacity'),
      'homeDnsDetailOpacity': settings.homeOpacity('home_dns_detail_opacity'),
      'homeSentenceRunning': sentences.running,
      'homeSentenceStopped': sentences.stopped,
      'customBackgroundUri': settings.customBackgroundUri,
    };
  }

  Map<String, Object?> _system(BackupExportSource source) {
    final settings = source.settings;
    final texts = settings.notificationTexts;
    return {
      'bypassLan': settings.bypassLanEnabled,
      'ipv6Mode': settings.ipv6ModeRaw,
      'logRetentionDays': settings.logRetentionDays,
      'dnsLogMode': settings.dnsLogModeRaw,
      'hideFromRecents': settings.hideFromRecentsEnabled,
      'floatingLogEnabled': settings.floatingLogEnabled,
      'floatingLogPanelSize': settings.rawValue('floating_log_panel_size'),
      'disableStartupUpdateCheck': settings.disableStartupUpdateCheck,
      'appLanguageMode': settings.appLanguageModeRaw,
      'notificationPersistent': settings.notificationPersistent,
      'notificationSpeed': settings.notificationSpeed,
      'notificationStatsItems': settings.notificationStatsItems,
      'customRunningNotificationText': texts.running,
      'customStoppedNotificationText': texts.stopped,
      'domainRulesEnabled': settings.domainRulesEnabled,
      'addressRulesEnabled': settings.addressRulesEnabled,
      'encryptedDnsBlockingEnabled': settings.encryptedDnsBlockingEnabled,
      'blockResponseMode': settings.blockResponseModeRaw,
      'allowEditDefaultWhitelist':
          settings.rawValue('allow_edit_default_whitelist') == true,
      'dynamicBlockResponse': {
        'enabled': settings.dynamicBlockEnabled,
        'requestThreshold': settings.dynamicBlockRequestThreshold,
        'windowSeconds': settings.dynamicBlockWindowSeconds,
        'nxDomainDurationSeconds': settings.dynamicBlockNxDomainDurationSeconds,
      },
      'appTrafficStatsEnabled':
          settings.rawValue('app_traffic_stats_enabled') != false,
      'trafficStatsRetentionDays':
          settings.rawValue('traffic_stats_retention_days') ?? 30,
      'trafficStatsHideSystemApps':
          settings.rawValue('traffic_stats_hide_system_apps') == true,
      'subscriptionAutoUpdateEnabled': settings.subscriptionAutoUpdateEnabled,
      'subscriptionAutoUpdateIntervalHours':
          settings.subscriptionAutoUpdateIntervalHours,
      'subscriptionAutoUpdateSchedule':
          settings.subscriptionAutoUpdateScheduleRaw,
      'subscriptionAutoUpdateTimeMinutes':
          settings.subscriptionAutoUpdateTimeMinutes,
    };
  }
}
