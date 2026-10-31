/// Translates the grouped backup into the flat structure the legacy app reads; field names must
/// match the legacy exporter exactly.
library;

import 'package:diting/data/backup/backup_models.dart';
import 'package:diting/data/backup/legacy_backup_json.dart';
import 'package:diting/data/prefs/legacy_settings.dart';

abstract final class LegacyBackupWriter {
  /// The legacy `ConfigTransferParser.FORMAT_VERSION`.
  static const int formatVersion = 10;

  /// Flat legacy root fields contributed by one group.
  ///
  /// The exporter streams the document, so these are written right after the group they come from
  /// instead of after every group has been read: the flat copy of a subscription-sized rule list is
  /// then produced and written before the grouped copy exists. Field names must still match the
  /// legacy exporter exactly.
  static Map<String, Object?> legacyOf(
    BackupGroup group,
    Object? value,
    LegacySettings settings,
  ) {
    final root = <String, Object?>{};
    switch (group) {
      case BackupGroup.providers:
        _putProviders(root, value);
      case BackupGroup.bootstrap:
        _putBootstrap(root, value);
      case BackupGroup.cache:
        _putCache(root, value);
      case BackupGroup.outbound:
        _putOutbound(root, value);
      case BackupGroup.subscriptions:
        _putSubscriptions(root, value);
      case BackupGroup.domainRules:
        _putDomainRules(root, value);
      case BackupGroup.rewriteDomain:
        _putRewrites(root, 'customRewriteDomainRules', value);
      case BackupGroup.rewriteCname:
        _putRewrites(root, 'customRewriteCnameRules', value);
      case BackupGroup.addressRules:
        _putAddressRules(root, value);
      case BackupGroup.system:
        _putFlatSwitches(root, value);
        _putSystem(root, value, settings);
      case BackupGroup.appearance:
        _putAppearance(root, value, settings);
      case BackupGroup.excluded:
      case BackupGroup.blocked:
      case BackupGroup.allowlist:
      case BackupGroup.httpInspection:
        // The four app lists share one legacy section; [appSectionsOf] writes it once.
        break;
    }
    return root;
  }

  /// The shared legacy app section, from whichever of the four list groups were selected.
  static Map<String, Object?> appSectionsOf(Map<String, Object?> byKey) {
    final root = <String, Object?>{};
    _putAppSections(root, byKey);
    return root;
  }

  static void _putProviders(Map<String, Object?> root, Object? value) {
    if (value is! Map) return;
    final items = value['items'];
    if (items is List) {
      final providers = <Object?>[];
      for (final item in items) {
        final provider = BackupJson.map(item);
        if (provider == null) continue;
        providers.add({
          'name': BackupJson.text(provider['name']) ?? '',
          'protocol': BackupJson.text(provider['protocol']) ?? 'DOH',
          'url': BackupJson.text(provider['url']) ?? '',
          'host': BackupJson.text(provider['host']) ?? '',
          'port': BackupJson.integer(provider['port']) ?? 853,
        });
      }
      root['providers'] = providers;
    }
    final selection = BackupJson.map(value['selection']);
    if (selection == null) return;
    final selected = BackupJson.map(selection['selectedProvider']);
    if (selected != null) {
      root['selectedProvider'] = {
        'id': BackupJson.text(selected['id']) ?? '',
        'name': BackupJson.text(selected['name']) ?? '',
        'protocol': BackupJson.text(selected['protocol']) ?? 'DOH',
        'isPreset': selected['isPreset'] == true,
      };
    }
    for (final key in const [
      'resolutionMode',
      'presetDnsService',
      'raceTestDomain',
    ]) {
      final text = BackupJson.text(selection[key]);
      if (text != null) root[key] = text;
    }
    for (final key in const [
      'raceProviderRefs',
      'smartPredictionProviderRefs',
      'parallelRaceProviderRefs',
      'primaryBackupProviderRefs',
      'latencyTestProviderRefs',
    ]) {
      final refs = selection[key];
      if (refs is List) root[key] = _refs(refs);
    }
    final visibility = BackupJson.map(selection['homeProviderVisibility']);
    if (visibility != null) {
      root['homeProviderVisibility'] = {
        'visibleProtocols': BackupJson.strings(visibility['visibleProtocols']),
        'hiddenProviderRefs': _refs(visibility['hiddenProviderRefs']),
        'visibleProviderRefs': _refs(visibility['visibleProviderRefs']),
      };
    }
  }

  static void _putBootstrap(Map<String, Object?> root, Object? value) {
    final bootstrap = BackupJson.map(value);
    if (bootstrap == null) return;
    if (bootstrap['enabled'] is bool) {
      root['bootstrapEnabled'] = bootstrap['enabled'];
    }
    final presetIds = bootstrap['presetIds'];
    if (presetIds is List) {
      root['bootstrapPresetIds'] = BackupJson.strings(presetIds);
    }
    // Always write the array: a missing key reads as an empty backup.
    final custom = bootstrap['custom'];
    if (custom is List) {
      final entries = <Object?>[];
      for (final item in custom) {
        final entry = BackupJson.map(item);
        if (entry == null) continue;
        entries.add({
          'name': BackupJson.text(entry['name']) ?? '',
          'ip': BackupJson.text(entry['ip']) ?? '',
          'enabled': entry['enabled'] != false,
        });
      }
      root['bootstrapIps'] = entries;
    } else {
      root['bootstrapIps'] = const <Object?>[];
    }
  }

  static void _putCache(Map<String, Object?> root, Object? value) {
    final cache = BackupJson.map(value);
    if (cache == null) return;
    root['dnsCache'] = {
      'enabled': cache['enabled'] == true,
      'preset': BackupJson.text(cache['preset']),
      'mode': BackupJson.text(cache['mode']),
      'maxTtlSeconds': BackupJson.integer(cache['maxTtlSeconds']) ?? 3600,
      'fixedTtlSeconds': BackupJson.integer(cache['fixedTtlSeconds']) ?? 3600,
      'minTtlEnabled': cache['minTtlEnabled'] == true,
      'minTtlSeconds': BackupJson.integer(cache['minTtlSeconds']) ?? 60,
      'staleFallbackEnabled': cache['staleFallbackEnabled'] == true,
      'staleFallbackSeconds':
          BackupJson.integer(cache['staleFallbackSeconds']) ?? 300,
    };
  }

  /// Credentials never enter a backup; `credentialsOmitted` says so explicitly.
  static void _putOutbound(Map<String, Object?> root, Object? value) {
    final outbound = BackupJson.map(value);
    if (outbound == null) return;
    root['outboundProxy'] = {
      'enabled': outbound['enabled'] == true,
      'protocol': BackupJson.text(outbound['protocol']) ?? 'socks5',
      'host': BackupJson.text(outbound['host']) ?? '127.0.0.1',
      'port': BackupJson.integer(outbound['port']) ?? 7890,
      'credentialsOmitted': true,
      'proxyAppPackage': BackupJson.text(outbound['proxyAppPackage']) ?? '',
    };
  }

  static void _putSubscriptions(Map<String, Object?> root, Object? value) {
    final subscriptions = BackupJson.map(value);
    if (subscriptions == null) return;
    // Always write the arrays, even empty: a missing key looks like data loss.
    root['mirrorTemplates'] = _templates(subscriptions['mirrorTemplates']);
    root['subscriptionGroups'] = _groups(subscriptions['groups']);
    root['subscriptions'] = _subscriptionItems(subscriptions['items']);
  }

  static List<Object?> _templates(Object? value) {
    if (value is! List) return const [];
    final result = <Object?>[];
    for (final item in value) {
      final template = BackupJson.map(item);
      if (template == null) continue;
      result.add({
        'name': BackupJson.text(template['name']) ?? '',
        'template': BackupJson.text(template['template']) ?? '',
      });
    }
    return result;
  }

  static List<Object?> _groups(Object? value) {
    if (value is! List) return const [];
    final result = <Object?>[];
    for (final item in value) {
      final group = BackupJson.map(item);
      if (group == null) continue;
      result.add({
        'name': BackupJson.text(group['name']) ?? '',
        'autoUpdateEnabled': group['autoUpdateEnabled'] != false,
      });
    }
    return result;
  }

  static List<Object?> _subscriptionItems(Object? value) {
    if (value is! List) return const [];
    final result = <Object?>[];
    for (final item in value) {
      final row = BackupJson.map(item);
      if (row == null) continue;
      final url = BackupJson.text(row['url']);
      if (url == null) continue;
      result.add({
        'name': BackupJson.text(row['name']) ?? url,
        'url': url,
        'kind': BackupJson.text(row['kind']) ?? 'domain',
        'scope': BackupJson.text(row['scope']) ?? 'dns',
        'mirrorTemplate': BackupJson.text(row['mirrorTemplate']),
        'mirrorFallback': row['mirrorFallback'] != false,
        'enabled': row['enabled'] != false,
        'groupName': BackupJson.text(row['groupName']),
      });
    }
    return result;
  }

  /// Block and allow share one list here, split by `kind`; legacy keeps two arrays.
  static void _putDomainRules(Map<String, Object?> root, Object? value) {
    if (value is! List) return;
    final block = <Object?>[];
    final allow = <Object?>[];
    for (final item in value) {
      final rule = BackupJson.map(item);
      if (rule == null) continue;
      final pattern = BackupJson.text(rule['pattern']);
      if (pattern == null) continue;
      final entry = {
        'pattern': pattern,
        'important': rule['important'] == true,
        'appScope': BackupJson.text(rule['appScope']),
        'appInverted': rule['appInverted'] == true,
        'rawLine': BackupJson.text(rule['rawLine']) ?? pattern,
        'enabled': rule['enabled'] != false,
      };
      if (BackupJson.text(rule['kind']) == 'allow') {
        allow.add(entry);
      } else {
        block.add(entry);
      }
    }
    root['customBlockRules'] = block;
    root['customAllowRules'] = allow;
  }

  static void _putRewrites(
    Map<String, Object?> root,
    String key,
    Object? value,
  ) {
    if (value is! List) return;
    final items = <Object?>[];
    for (final item in value) {
      final rule = BackupJson.map(item);
      if (rule == null) continue;
      final pattern = BackupJson.text(rule['pattern']);
      final targetValue = BackupJson.text(rule['targetValue']);
      if (pattern == null || targetValue == null) continue;
      items.add({
        'pattern': pattern,
        'targetType': BackupJson.text(rule['targetType']) ?? 'CNAME',
        'targetValue': targetValue,
        'rawLine': BackupJson.text(rule['rawLine']) ?? '$pattern $targetValue',
        'enabled': rule['enabled'] != false,
      });
    }
    root[key] = items;
  }

  static void _putAddressRules(Map<String, Object?> root, Object? value) {
    if (value is! List) return;
    final items = <Object?>[];
    for (final item in value) {
      final rule = BackupJson.map(item);
      if (rule == null) continue;
      final pattern = BackupJson.text(rule['pattern']);
      if (pattern == null) continue;
      items.add({
        'pattern': pattern,
        'kind': BackupJson.text(rule['kind']) ?? 'block',
        'rawLine': BackupJson.text(rule['rawLine']) ?? pattern,
        'enabled': rule['enabled'] != false,
      });
    }
    root['customAddressRules'] = items;
  }

  static void _putAppSections(
    Map<String, Object?> root,
    Map<String, Object?> data,
  ) {
    root['excludedApps'] = BackupJson.strings(data[BackupGroup.excluded.key]);
    final blocked = BackupJson.map(data[BackupGroup.blocked.key]);
    root['blockedApps'] = BackupJson.strings(blocked?['packages']);
    root['blockedAppsEnabled'] = blocked?['enabled'] == true;
    final allowlist = BackupJson.map(data[BackupGroup.allowlist.key]);
    if (allowlist != null) {
      final rules = BackupJson.map(allowlist['rules']);
      root['appAllowlistRules'] = {
        for (final entry
            in rules?.entries ?? const <MapEntry<Object?, Object?>>[])
          '${entry.key}': BackupJson.strings(entry.value),
      };
      root['appAllowlistEnabled'] = allowlist['enabled'] == true;
    }
    final inspection = BackupJson.map(data[BackupGroup.httpInspection.key]);
    if (inspection != null) {
      root['httpInspection'] = {
        'enabled': inspection['enabled'] == true,
        'http3Enabled': inspection['http3Enabled'] == true,
        'appPackages': BackupJson.strings(inspection['packages']),
      };
    }
  }

  /// Flat root keys in the legacy format, not inside `systemSettings`.
  static void _putFlatSwitches(Map<String, Object?> root, Object? value) {
    final system = BackupJson.map(value);
    root['domainRulesEnabled'] = system?['domainRulesEnabled'] != false;
    root['addressRulesEnabled'] = system?['addressRulesEnabled'] != false;
    root['encryptedDnsBlockingEnabled'] =
        system?['encryptedDnsBlockingEnabled'] == true;
    root['blockResponseMode'] =
        BackupJson.text(system?['blockResponseMode']) ?? 'nxdomain';
    root['allowEditDefaultWhitelist'] =
        system?['allowEditDefaultWhitelist'] == true;
    final dynamicBlock = BackupJson.map(system?['dynamicBlockResponse']);
    root['dynamicBlockResponse'] = {
      'enabled': dynamicBlock?['enabled'] == true,
      'requestThreshold':
          BackupJson.integer(dynamicBlock?['requestThreshold']) ?? 5,
      'windowSeconds': BackupJson.integer(dynamicBlock?['windowSeconds']) ?? 60,
      'nxDomainDurationSeconds':
          BackupJson.integer(dynamicBlock?['nxDomainDurationSeconds']) ?? 300,
    };
    root['subscriptionAutoUpdate'] = {
      'enabled': system?['subscriptionAutoUpdateEnabled'] == true,
      'intervalHours':
          BackupJson.integer(system?['subscriptionAutoUpdateIntervalHours']) ??
          24,
    };
  }

  static List<Object?> _refs(Object? value) {
    if (value is! List) return const [];
    final result = <Object?>[];
    for (final item in value) {
      final ref = BackupJson.map(item);
      if (ref == null) continue;
      result.add({
        'id': BackupJson.text(ref['id']) ?? '',
        'name': BackupJson.text(ref['name']) ?? '',
        'protocol': BackupJson.text(ref['protocol']) ?? 'DOH',
        'isPreset': ref['isPreset'] == true,
      });
    }
    return result;
  }

  /// Backup value, else the local one: the legacy parser defaults missing keys.
  static void _putAppearance(
    Map<String, Object?> root,
    Object? value,
    LegacySettings settings,
  ) {
    final appearance = BackupJson.map(value);
    if (appearance == null) return;
    final sentences = settings.homeSentences;
    final base = settings.componentOpacity;
    root['appearance'] = {
      'appThemeMode':
          BackupJson.text(appearance['themeMode']) ?? settings.themeModeRaw,
      'themeColorStyle':
          BackupJson.text(appearance['palette']) ?? settings.paletteRaw,
      'homeComponentOpacity':
          BackupJson.decimal(appearance['componentOpacity']) ?? base,
      'homePowerButtonOpacity':
          BackupJson.decimal(appearance['homePowerButtonOpacity']) ?? base,
      'homeProviderSelectorOpacity':
          BackupJson.decimal(appearance['homeProviderSelectorOpacity']) ?? base,
      'homeModeButtonOpacity':
          BackupJson.decimal(appearance['homeModeButtonOpacity']) ?? base,
      'homePoemOpacity':
          BackupJson.decimal(appearance['homePoemOpacity']) ??
          settings.homeOpacity('home_poem_opacity'),
      'homeDnsDetailOpacity':
          BackupJson.decimal(appearance['homeDnsDetailOpacity']) ??
          settings.homeOpacity('home_dns_detail_opacity'),
      'homeSentenceRunning':
          BackupJson.text(appearance['homeSentenceRunning']) ??
          sentences.running,
      'homeSentenceStopped':
          BackupJson.text(appearance['homeSentenceStopped']) ??
          sentences.stopped,
    };
  }

  /// Same fallback, so a legacy import does not reset settings.
  static void _putSystem(
    Map<String, Object?> root,
    Object? value,
    LegacySettings settings,
  ) {
    final system = BackupJson.map(value);
    if (system == null) return;
    root['systemSettings'] = {
      'bypassLanEnabled': system['bypassLan'] == true,
      'ipv6Mode': BackupJson.text(system['ipv6Mode']) ?? settings.ipv6ModeRaw,
      'hideFromRecentsEnabled': system['hideFromRecents'] == true,
      'logRetentionDays':
          BackupJson.integer(system['logRetentionDays']) ??
          settings.logRetentionDays,
      'dnsLogMode':
          BackupJson.text(system['dnsLogMode']) ?? settings.dnsLogModeRaw,
      'floatingLogEnabled': system['floatingLogEnabled'] == true,
      'floatingLogPanelSize':
          BackupJson.integer(system['floatingLogPanelSize']) ?? 0,
      'appTrafficStatsEnabled': system['appTrafficStatsEnabled'] != false,
      'trafficStatsRetentionDays':
          BackupJson.integer(system['trafficStatsRetentionDays']) ?? 30,
      'trafficStatsHideSystemApps':
          system['trafficStatsHideSystemApps'] == true,
      'disableStartupUpdateCheck': system['disableStartupUpdateCheck'] != false,
      'appLanguageMode':
          BackupJson.text(system['appLanguageMode']) ??
          settings.appLanguageModeRaw,
      'persistentNotificationEnabled':
          system['notificationPersistent'] != false,
      'trafficSpeedEnabled': system['notificationSpeed'] == true,
      'customRunningNotificationText':
          BackupJson.text(system['customRunningNotificationText']) ??
          settings.notificationTexts.running,
      'customStoppedNotificationText':
          BackupJson.text(system['customStoppedNotificationText']) ??
          settings.notificationTexts.stopped,
      'domainRulesEnabled': system['domainRulesEnabled'] != false,
      'addressRulesEnabled': system['addressRulesEnabled'] != false,
      'encryptedDnsBlockingEnabled':
          system['encryptedDnsBlockingEnabled'] == true,
      'blockResponseMode':
          BackupJson.text(system['blockResponseMode']) ?? 'nxdomain',
      'allowEditDefaultWhitelist': system['allowEditDefaultWhitelist'] == true,
      'dynamicBlockResponse':
          BackupJson.map(system['dynamicBlockResponse']) ??
          const {
            'enabled': false,
            'requestThreshold': 5,
            'windowSeconds': 60,
            'nxDomainDurationSeconds': 300,
          },
    };
  }
}
