part of 'backup_importer.dart';


extension _BackupImportApply on BackupImporter {
  Future<void> _applyPlan(
    Map<String, Object?> answer,
    BackupImportTarget target,
    DateTime now,
  ) async {
    final settings = target.settings;
    for (final write in answer['writes'] as List? ?? const []) {
      if (write is! Map) continue;
      _applyWrite(settings, target, write, now);
    }
    final db = target.database;
    final groupIds = <String, int>{};
    for (final op in answer['ops'] as List? ?? const []) {
      if (op is! Map || db == null) continue;
      await _applyOp(db, op, groupIds);
    }
  }

  void _applyWrite(
    LegacySettings settings,
    BackupImportTarget target,
    Map write,
    DateTime now,
  ) {
    final store = target.store;
    final value = write['value'];
    switch ('${write['field']}') {
      case 'providers.items':
        settings.setUserProvidersJson('$value');
      case 'providers.selectedId':
        settings.setSelectedProviderId('$value');
      case 'providers.resolutionMode':
        settings.setResolutionModeRaw('$value');
      case 'providers.raceTestDomain':
        settings.setRaceTestDomain('$value');
      case 'providers.race':
        settings.setRaceProviderIds(_strings(value));
      case 'providers.smartPrediction':
        settings.setSmartPredictionProviderIds(_strings(value));
      case 'providers.parallelRace':
        settings.setParallelRaceProviderIds(_strings(value));
      case 'providers.primaryBackup':
        settings.setPrimaryBackupProviderIds(_strings(value));
      case 'providers.latencyTest':
        settings.setLatencyTestProviderIds(_strings(value));
      case 'providers.homeVisibility':
        final record = value as Map;
        settings.setHomeProviderVisibility(
          visibleProtocols: _strings(record['visibleProtocols']).toSet(),
          hiddenProviderIds: _strings(record['hiddenProviderIds']).toSet(),
          visibleProviderIds: _strings(record['visibleProviderIds']).toSet(),
        );
      case 'bootstrap.enabled':
        settings.setBootstrapEnabled(value == true);
      case 'bootstrap.presetIds':
        settings.setBootstrapPresetIds(_strings(value).toSet());
      case 'bootstrap.customJson':
        settings.setBootstrapCustomJson('$value');
      case 'cache.config':
        final record = value as Map;
        final tier =
            DnsCacheTier.fromStorage('${record['preset']}') ??
            DnsCacheTier.standard;
        final percent = switch (record['ttlScalePercent']) {
          final num value => value.toInt(),
          _ => tier.defaultScalePercent,
        };
        DnsCachePolicy(
          tier: tier,
          scalePercent: percent,
        ).write(settings, enabled: record['enabled'] == true);
      case 'outbound.protocol':
        store.putString(
          LegacySettings.uiContainer,
          'outbound_proxy_protocol',
          '$value',
        );
      case 'outbound.host':
        store.putString(
          LegacySettings.uiContainer,
          'outbound_proxy_host',
          '$value',
        );
      case 'outbound.app':
        store.putString(
          LegacySettings.uiContainer,
          'outbound_proxy_app',
          '$value',
        );
      case 'outbound.port':
        store.putInt(
          LegacySettings.uiContainer,
          'outbound_proxy_port',
          value as int,
        );
      case 'excluded.packages':
        settings.setExcludedPackages(_strings(value).toSet());
      case 'blocked.packages':
        settings.setBlockedApps(
          packages: _strings(value).toSet(),
          enabled: settings.blockedAppsEnabled,
        );
      case 'blocked.enabled':
        settings.setBlockedApps(
          packages: settings.blockedAppPackages,
          enabled: value == true,
        );
      case 'allowlist.rules':
        settings.setAppAllowlistRules({
          for (final entry in (value as Map).entries)
            '${entry.key}': _strings(entry.value).toSet(),
        });
      case 'allowlist.enabled':
        settings.setAppAllowlistEnabled(value == true);
      case 'httpInspection.packages':
        settings.setHttpInspectionApps(
          packages: _strings(value).toSet(),
          enabled: settings.httpInspectionEnabled,
        );
      case 'httpInspection.http3':
        settings.setHttpInspectionToggles(
          http3: value == true,
          encryptedDns: settings.encryptedDnsBlockingEnabled,
          addressRules: settings.addressRulesEnabled,
        );
      case 'appearance.themeMode':
        settings.setThemeModeRaw('$value');
      case 'appearance.palette':
        settings.setPaletteRaw('$value');
      case 'appearance.bottomBarIds':
        settings.setBottomBarIds(_strings(value));
      case 'appearance.liquidGlassMode':
        settings.setLiquidGlassModeRaw('$value');
      case 'appearance.hapticEnabled':
        settings.setHapticEnabled(value == true);
      case 'appearance.homeOpacity':
        final record = value as Map;
        settings.setHomeOpacity(
          '${record['key']}',
          (record['value'] as num).toDouble(),
        );
      case 'appearance.componentOpacity':
        settings.setHomeComponentOpacity((value as num).toDouble());
      case 'appearance.homeSentences':
        final record = value as Map;
        settings.setHomeSentences(
          running: '${record['running']}',
          stopped: '${record['stopped']}',
        );
      case 'system.bypassLan':
        settings.setBypassLanEnabled(value == true);
      case 'system.tunnelIpv6':
        settings.setTunnelIpv6Enabled(value == true);
      case 'system.dnsAaaa':
        settings.setDnsAaaaEnabled(value == true);
      case 'system.routeAddress':
        settings.setVpnRouteAddress(_strings(value));
      case 'system.routeExcludeAddress':
        settings.setVpnRouteExcludeAddress(_strings(value));
      case 'system.logRetentionDays':
        settings.setLogRetentionDays(value as int);
      case 'system.dnsLogMode':
        settings.setDnsLogModeRaw('$value');
      case 'system.hideFromRecents':
        settings.setHideFromRecentsEnabled(value == true);
      case 'system.floatingLogEnabled':
        settings.setFloatingLogEnabled(value == true);
      case 'system.floatingLogPanelSize':
        settings.setFloatingLogPanelSize(value as int);
      case 'system.disableStartupUpdateCheck':
        settings.setDisableStartupUpdateCheck(value == true);
      case 'system.appLanguageMode':
        settings.setAppLanguageModeRaw('$value');
      case 'system.notificationPersistent':
        settings.setNotificationPersistent(value == true);
      case 'system.notificationSpeed':
        settings.setNotificationSpeed(value == true);
      case 'system.notificationStatsItems':
        settings.setNotificationStatsItems(_strings(value));
      case 'system.notificationTexts':
        final record = value as Map;
        settings.setNotificationTexts(
          running: '${record['running']}',
          stopped: '${record['stopped']}',
        );
      case 'system.domainRulesEnabled':
        settings.setDomainRulesEnabled(value == true);
      case 'system.httpInspectionToggles':
        final record = value as Map;
        settings.setHttpInspectionToggles(
          http3: record['http3'] == true,
          encryptedDns: record['encryptedDns'] == true,
          addressRules: record['addressRules'] == true,
        );
      case 'system.blockResponseMode':
        settings.setBlockResponseModeRaw('$value');
      case 'system.allowEditDefaultWhitelist':
        store.putBool(
          LegacySettings.uiContainer,
          'allow_edit_default_whitelist',
          value == true,
        );
      case 'system.dynamicBlockPolicy':
        final record = value as Map;
        settings.setDynamicBlockPolicy(
          enabled: record['enabled'] == true,
          requestThreshold: record['requestThreshold'] as int? ?? 0,
          windowSeconds: record['windowSeconds'] as int? ?? 0,
          nxDurationSeconds: record['nxDomainDurationSeconds'] as int? ?? 0,
        );
      case 'system.trafficStats':
        final record = value as Map;
        final key = '${record['key']}';
        final raw = record['value'];
        if (raw is bool) {
          store.putBool(LegacySettings.uiContainer, key, raw);
        } else if (raw is int) {
          store.putInt(LegacySettings.uiContainer, key, raw);
        }
      case 'system.subscriptionAutoUpdateEnabled':
        settings.setSubscriptionAutoUpdateEnabled(value == true);
      case 'system.subscriptionAutoUpdateIntervalHours':
        settings.setSubscriptionAutoUpdateIntervalHours(value as int);
      case 'system.subscriptionAutoUpdateSchedule':
        final record = value as Map;
        settings.setSubscriptionAutoUpdateScheduleRaw('${record['schedule']}');
        settings.setSubscriptionAutoUpdateTimeMinutes(
          record['timeMinutes'] as int? ?? 0,
        );
        settings.setSubscriptionAutoUpdateSinceMs(now.millisecondsSinceEpoch);
      default:
        debugPrint('backup import: unknown write ${write['field']}');
    }
  }

  Future<void> _applyOp(Database db, Map op, Map<String, int> groupIds) async {
    switch ('${op['op']}') {
      case 'subsGroup':
        final id = await SubscriptionRepository(db).insertGroup(
          name: '${op['name']}',
          autoUpdateEnabled: op['autoUpdateEnabled'] != false,
        );
        groupIds['${op['name']}'] = id;
      case 'subsMirror':
        await db.insert('mirror_template', {
          'name': op['name'],
          'template': op['template'],
          'addedAt': op['addedAt'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      case 'subsItem':
        final groupName = op['groupName'];
        await SubscriptionRepository(db).insert(
          SubscriptionRecord(
            id: 0,
            url: '${op['url']}',
            name: '${op['name']}',
            sourceType: SubscriptionSourceType.fromStorage(
              op['sourceType'] as String?,
            ),
            kind: SubscriptionKind.normalize(op['kind'] as String?),
            enabled: op['enabled'] != false,
            ruleCount: op['ruleCount'] as int? ?? 0,
            lastUpdated: op['lastUpdated'] as int? ?? 0,
            addedAt: op['addedAt'] as int? ?? 0,
            importState: SubscriptionImportState.ready,
            lastAttemptAt: 0,
            consecutiveFailureCount: 0,
            mirrorTemplate: op['mirrorTemplate'] as String?,
            mirrorFallback: op['mirrorFallback'] != false,
            groupId: groupName is String ? groupIds[groupName] : null,
          ),
        );
      case 'ruleInsert':
        await _insertDomainRule(
          db,
          '${op['table']}',
          op['row'] as Map<String, Object?>,
        );
      case 'rewriteInsert':
        await _insertRule(
          db,
          table: 'rewrite_rule',
          sourceTable: 'rewrite_rule_source',
          row: op['row'] as Map<String, Object?>,
        );
      case 'rewriteUpdate':
        await db.update(
          'rewrite_rule',
          {'targetValue': op['targetValue'], 'rawLine': op['rawLine']},
          where: 'id = ?',
          whereArgs: [op['id']],
        );
      case 'addressInsert':
        await _insertRule(
          db,
          table: 'go_url_rule',
          sourceTable: 'go_url_rule_source',
          row: op['row'] as Map<String, Object?>,
        );
      default:
        debugPrint('backup import: unknown op ${op['op']}');
    }
  }

  Future<void> _insertDomainRule(
    Database db,
    String table,
    Map<String, Object?> row,
  ) async {
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.ignore);
    final pattern = row['pattern'];
    final important = row['important'];
    final appScope = row['appScope'];
    final rows = await db.query(
      table,
      columns: ['id'],
      where: appScope == null
          ? 'pattern = ? AND important = ? AND appScope IS NULL'
          : 'pattern = ? AND important = ? AND appScope = ?',
      whereArgs: [pattern, important, ?appScope],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await _insertRuleSource(db, '${table}_source', rows.first['id']);
  }

  Future<void> _insertRule(
    Database db, {
    required String table,
    required String sourceTable,
    required Map<String, Object?> row,
  }) async {
    final id = await db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (id == 0) return;
    await _insertRuleSource(db, sourceTable, id);
  }

  Future<void> _insertRuleSource(Database db, String table, Object? ruleId) =>
      db.insert(table, {
        'ruleId': ruleId,
        'source': 'useradd',
        'enabled': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

  static List<String> _strings(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is String) item,
  ];
}
