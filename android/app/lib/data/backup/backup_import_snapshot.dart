part of 'backup_importer.dart';

// The local side of the merge: the core compares the file against these values, so this is where
// the app's storage layout (containers, raw keys, table columns) is described. Nothing here decides
// anything — an absent value means "not set on this device".
//
// Rule rows are read unfiltered by source on purpose: a preset rule that the user also added counts
// as present, which is what the dedupe key checks.

extension _BackupImportSnapshot on BackupImporter {
  Future<Map<String, Object?>> _current(BackupImportTarget target) async {
    final settings = target.settings;
    final store = target.store;
    final db = target.database;
    // Both rewrite groups read one table.
    List<Map<String, Object?>>? rewriteRows;
    return {
      'providers': {
        'itemsJson': settings.userProvidersJson,
        'presets': [
          for (final provider in defaultDnsProviders(currentL10n))
            {
              'id': provider.id,
              'name': provider.name,
              'protocol': provider.protocol.storageValue,
            },
        ],
        'homeVisibleProtocols': settings.homeVisibleProtocols.toList(),
      },
      'bootstrap': {
        'enabled': settings.bootstrapEnabled,
        'presetIds': settings.bootstrapPresetIds,
        'customJson': settings.bootstrapCustomJson,
      },
      'cache': {
        'enabled': settings.cacheEnabled,
        'mode': settings.cacheModeRaw,
        'maxTtlSeconds': settings.cacheMaxTtlSeconds,
        'fixedTtlSeconds': settings.cacheFixedTtlSeconds,
        'minTtlEnabled': settings.cacheMinTtlEnabled,
        'minTtlSeconds': settings.cacheMinTtlSeconds,
        'staleFallbackEnabled': settings.cacheStaleFallbackEnabled,
        'staleFallbackSeconds': settings.cacheStaleFallbackSeconds,
        'preset': settings.cachePresetRaw,
      },
      'outbound': {
        'protocol': store.read(
          LegacySettings.uiContainer,
          'outbound_proxy_protocol',
        ),
        'host': store.read(LegacySettings.uiContainer, 'outbound_proxy_host'),
        'port': store.read(LegacySettings.uiContainer, 'outbound_proxy_port'),
        'proxyAppPackage': store.read(
          LegacySettings.uiContainer,
          'outbound_proxy_app',
        ),
      },
      'subscriptions': await _subscriptions(db),
      'domainRules': await _domainRules(db),
      'rewriteDomain': {'rows': rewriteRows ??= await _rewriteRows(db)},
      'rewriteCname': {'rows': rewriteRows},
      'addressRules': await _addressRules(db),
      'excluded': {'packages': settings.excludedPackages.toList()},
      'blocked': {
        'enabled': settings.blockedAppsEnabled,
        'packages': settings.blockedAppPackages.toList(),
      },
      'allowlist': {
        'enabled': settings.appAllowlistEnabled,
        'rules': {
          for (final entry in settings.appAllowlistRules.entries)
            entry.key: entry.value.toList(),
        },
      },
      'httpInspection': {
        'enabled': settings.httpInspectionEnabled,
        'http3Enabled': settings.http3InspectionEnabled,
        'packages': settings.httpInspectionPackages.toList(),
      },
      'appearance': {
        'themeMode': settings.themeModeRaw,
        'palette': settings.paletteRaw,
        'liquidGlassMode': settings.liquidGlassModeRaw,
        'hapticEnabled': settings.hapticEnabled,
        'bottomBarIds': settings.bottomBarIds,
        'componentOpacity': settings.componentOpacity,
        'homePowerButtonOpacity': settings.homeOpacity(
          'home_power_button_opacity',
        ),
        'homeProviderSelectorOpacity': settings.homeOpacity(
          'home_provider_selector_opacity',
        ),
        'homeModeButtonOpacity': settings.homeOpacity('home_mode_button_opacity'),
        'homePoemOpacity': settings.homeOpacity('home_poem_opacity'),
        'homeDnsDetailOpacity': settings.homeOpacity('home_dns_detail_opacity'),
        'homeSentenceRunning': settings.homeSentences.running,
        'homeSentenceStopped': settings.homeSentences.stopped,
      },
      'system': {
        'bypassLan': settings.bypassLanEnabled,
        'ipv6Mode': settings.ipv6ModeRaw,
        'logRetentionDays': settings.logRetentionDays,
        'dnsLogMode': settings.dnsLogModeRaw,
        'hideFromRecents': settings.hideFromRecentsEnabled,
        'floatingLogEnabled': settings.floatingLogEnabled,
        // Stored raw, so "never touched" stays distinguishable from "set to the default".
        'floating_log_panel_size': store.read(
          LegacySettings.uiContainer,
          'floating_log_panel_size',
        ),
        'disableStartupUpdateCheck': settings.disableStartupUpdateCheck,
        'appLanguageMode': settings.appLanguageModeRaw,
        'notificationPersistent': settings.notificationPersistent,
        'notificationSpeed': settings.notificationSpeed,
        'notificationStatsItems': settings.notificationStatsItems,
        'customRunningNotificationText': settings.notificationTexts.running,
        'customStoppedNotificationText': settings.notificationTexts.stopped,
        'domainRulesEnabled': settings.domainRulesEnabled,
        'addressRulesEnabled': settings.addressRulesEnabled,
        'encryptedDnsBlockingEnabled': settings.encryptedDnsBlockingEnabled,
        'http3Enabled': settings.http3InspectionEnabled,
        'blockResponseMode': settings.blockResponseModeRaw,
        'allow_edit_default_whitelist': store.read(
          LegacySettings.uiContainer,
          'allow_edit_default_whitelist',
        ),
        'dynamicBlockResponse': {
          'enabled': settings.dynamicBlockEnabled,
          'requestThreshold': settings.dynamicBlockRequestThreshold,
          'windowSeconds': settings.dynamicBlockWindowSeconds,
          'nxDomainDurationSeconds':
              settings.dynamicBlockNxDomainDurationSeconds,
        },
        'app_traffic_stats_enabled': store.read(
          LegacySettings.uiContainer,
          'app_traffic_stats_enabled',
        ),
        'traffic_stats_retention_days': store.read(
          LegacySettings.uiContainer,
          'traffic_stats_retention_days',
        ),
        'traffic_stats_hide_system_apps': store.read(
          LegacySettings.uiContainer,
          'traffic_stats_hide_system_apps',
        ),
        'subscriptionAutoUpdateEnabled': settings.subscriptionAutoUpdateEnabled,
        'subscriptionAutoUpdateIntervalHours':
            settings.subscriptionAutoUpdateIntervalHours,
        'subscriptionAutoUpdateSchedule':
            settings.subscriptionAutoUpdateScheduleRaw,
        'subscriptionAutoUpdateTimeMinutes':
            settings.subscriptionAutoUpdateTimeMinutes,
      },
    };
  }

  Future<Map<String, Object?>> _subscriptions(Database? db) async {
    if (db == null) return const {'groupNames': [], 'urls': []};
    final repository = SubscriptionRepository(db);
    return {
      'groupNames': [for (final group in await repository.groups()) group.name],
      'urls': [
        for (final row in await repository.all())
          {'url': row.url, 'kind': row.kind.storageValue},
      ],
    };
  }

  Future<Map<String, Object?>> _domainRules(Database? db) async => {
    'block': await _ruleRows(db, 'block_rule'),
    'allow': await _ruleRows(db, 'allow_rule'),
  };

  Future<List<Map<String, Object?>>> _ruleRows(
    Database? db,
    String table,
  ) async {
    if (db == null) return const [];
    return db.query(
      table,
      columns: ['pattern', 'important', 'appScope'],
    );
  }

  Future<List<Map<String, Object?>>> _rewriteRows(Database? db) async {
    if (db == null) return const [];
    return db.query(
      'rewrite_rule',
      columns: ['id', 'pattern', 'targetType', 'targetValue'],
    );
  }

  Future<Map<String, Object?>> _addressRules(Database? db) async => {
    'rows': db == null
        ? const <Map<String, Object?>>[]
        : await db.query('go_url_rule', columns: ['pattern', 'kind']),
  };
}
