/// Reads the legacy flat backup (`formatVersion: 10`) into the current grouped `data` map, so both
/// formats share the importer's merge logic.
library;

import 'package:diting_android/data/backup/backup_models.dart';
import 'package:diting_android/data/backup/legacy_backup_json.dart';

abstract final class LegacyBackupReader {
  /// The legacy `ConfigTransferParser.FORMAT_VERSION`.
  static const int formatVersion = 10;

  static const int minFormatVersion = 1;

  static bool looksLegacy(Map<Object?, Object?> root) {
    final version = root['formatVersion'];
    return version is num && version >= minFormatVersion;
  }

  /// Translates a legacy flat backup; [providerId] derives an id per index.
  static Map<String, Object?> toGroups(
    Map<Object?, Object?> root, {
    required String Function(int index) providerId,
  }) {
    final data = <String, Object?>{};
    _put(data, BackupGroup.providers, _providers(root, providerId));
    _put(data, BackupGroup.bootstrap, _bootstrap(root));
    final cache = BackupJson.map(root['dnsCache']);
    if (cache != null) _put(data, BackupGroup.cache, _cache(cache));
    final outbound = BackupJson.map(root['outboundProxy']);
    if (outbound != null) _put(data, BackupGroup.outbound, _outbound(outbound));
    _put(data, BackupGroup.subscriptions, _subscriptions(root));

    final domainRules = <Object?>[
      ..._rules(root['customBlockRules'], 'block'),
      ..._rules(root['customAllowRules'], 'allow'),
    ];
    if (domainRules.isNotEmpty) {
      _put(data, BackupGroup.domainRules, domainRules);
    }
    _put(
      data,
      BackupGroup.rewriteDomain,
      _rewrites(root['customRewriteDomainRules'], const {'IPv4', 'IPv6'}),
    );
    _put(
      data,
      BackupGroup.rewriteCname,
      _rewrites(root['customRewriteCnameRules'], const {'CNAME'}),
    );
    _put(
      data,
      BackupGroup.addressRules,
      _addressRules(root['customAddressRules']),
    );

    // The legacy app writes these keys even with nothing blocked.
    _put(data, BackupGroup.excluded, BackupJson.strings(root['excludedApps']));
    if (root.containsKey('blockedApps')) {
      _put(data, BackupGroup.blocked, {
        'enabled': root['blockedAppsEnabled'] == true,
        'packages': BackupJson.strings(root['blockedApps']),
      });
    }
    final allowlist = BackupJson.map(root['appAllowlistRules']);
    if (allowlist != null) {
      _put(data, BackupGroup.allowlist, {
        'enabled': root['appAllowlistEnabled'] == true,
        'rules': {
          for (final entry in allowlist.entries)
            '${entry.key}': BackupJson.strings(entry.value),
        },
      });
    }
    final inspection = BackupJson.map(root['httpInspection']);
    if (inspection != null) {
      _put(data, BackupGroup.httpInspection, {
        'enabled': inspection['enabled'] == true,
        'http3Enabled': inspection['http3Enabled'] == true,
        'packages': BackupJson.strings(inspection['appPackages']),
      });
    }
    final appearance = BackupJson.map(root['appearance']);
    if (appearance != null) {
      _put(data, BackupGroup.appearance, _appearance(appearance));
    }
    final system = BackupJson.map(root['systemSettings']);
    if (system != null) _put(data, BackupGroup.system, _system(system));
    return data;
  }

  static void _put(
    Map<String, Object?> data,
    BackupGroup group,
    Object? value,
  ) {
    if (value == null) return;
    data[group.key] = value;
  }

  static Object? _providers(
    Map<Object?, Object?> root,
    String Function(int index) providerId,
  ) {
    final items = <Object?>[];
    final raw = root['providers'];
    if (raw is List) {
      var index = 0;
      for (final item in raw) {
        final provider = BackupJson.map(item);
        if (provider == null) continue;
        final name = BackupJson.text(provider['name']);
        final protocol = BackupJson.text(provider['protocol']);
        if (name == null || protocol == null) continue;
        items.add({
          'id': providerId(index++),
          'name': name,
          'protocol': protocol.toUpperCase(),
          'url': BackupJson.text(provider['url']) ?? '',
          'host': BackupJson.text(provider['host']) ?? '',
          'port': BackupJson.integer(provider['port']) ?? 853,
        });
      }
    }
    final selection = _selection(root);
    if (items.isEmpty && selection.isEmpty) return null;
    return {'items': items, 'selection': selection};
  }

  static Map<String, Object?> _selection(Map<Object?, Object?> root) {
    final selection = <String, Object?>{};
    final selected = BackupJson.map(root['selectedProvider']);
    if (selected != null) {
      selection['selectedProvider'] = {
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
      final value = BackupJson.text(root[key]);
      if (value != null) selection[key] = value;
    }
    for (final key in const [
      'raceProviderRefs',
      'smartPredictionProviderRefs',
      'parallelRaceProviderRefs',
      'primaryBackupProviderRefs',
      'latencyTestProviderRefs',
    ]) {
      final refs = root[key];
      if (refs is List) selection[key] = _refs(refs);
    }
    final visibility = BackupJson.map(root['homeProviderVisibility']);
    if (visibility != null) {
      selection['homeProviderVisibility'] = {
        'visibleProtocols': BackupJson.strings(visibility['visibleProtocols']),
        'hiddenProviderRefs': _refs(visibility['hiddenProviderRefs']),
        'visibleProviderRefs': _refs(visibility['visibleProviderRefs']),
      };
    }
    return selection;
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

  static Object? _bootstrap(Map<Object?, Object?> root) {
    final presets = root['bootstrapPresetIds'];
    final ips = root['bootstrapIps'];
    final enabled = root['bootstrapEnabled'];
    if (presets is! List && ips is! List && enabled is! bool) return null;
    final custom = <Object?>[];
    if (ips is List) {
      var index = 0;
      for (final item in ips) {
        final entry = BackupJson.map(item);
        if (entry == null) continue;
        final ip = BackupJson.text(entry['ip']);
        if (ip == null) continue;
        custom.add({
          'id': 'bootstrap_custom_${index++}',
          'name': BackupJson.text(entry['name']) ?? ip,
          'ip': ip,
          'enabled': entry['enabled'] != false,
        });
      }
    }
    return {
      if (enabled is bool) 'enabled': enabled,
      if (presets is List) 'presetIds': BackupJson.strings(presets),
      'custom': custom,
    };
  }

  static Map<String, Object?> _cache(Map<Object?, Object?> cache) => {
    'enabled': cache['enabled'],
    'mode': cache['mode'],
    'maxTtlSeconds': BackupJson.integer(cache['maxTtlSeconds']),
    'fixedTtlSeconds': BackupJson.integer(cache['fixedTtlSeconds']),
    'minTtlEnabled': cache['minTtlEnabled'],
    'minTtlSeconds': BackupJson.integer(cache['minTtlSeconds']),
    'staleFallbackEnabled': cache['staleFallbackEnabled'],
    'staleFallbackSeconds': BackupJson.integer(cache['staleFallbackSeconds']),
    'preset': cache['preset'],
  };

  /// The legacy file spells the app package `proxyAppPackage`; only the name differs.
  static Map<String, Object?> _outbound(Map<Object?, Object?> outbound) => {
    'enabled': outbound['enabled'] == true,
    'protocol': BackupJson.text(outbound['protocol']),
    'host': BackupJson.text(outbound['host']),
    'port': BackupJson.integer(outbound['port']),
    'proxyAppPackage': BackupJson.text(outbound['proxyAppPackage']),
    'credentialsExcluded': true,
  };

  static Object? _subscriptions(Map<Object?, Object?> root) {
    final subscriptions = root['subscriptions'];
    final groups = root['subscriptionGroups'];
    final templates = root['mirrorTemplates'];
    if (subscriptions is! List && groups is! List && templates is! List) {
      return null;
    }
    return {
      'groups': _groupItems(groups),
      'items': _subscriptionItems(subscriptions),
      'mirrorTemplates': _templateItems(templates),
    };
  }

  static List<Object?> _groupItems(Object? groups) {
    if (groups is! List) return const [];
    final result = <Object?>[];
    for (final item in groups) {
      final group = BackupJson.map(item);
      if (group == null) continue;
      result.add({
        'name': BackupJson.text(group['name']) ?? '',
        'autoUpdateEnabled': group['autoUpdateEnabled'] != false,
      });
    }
    return result;
  }

  static List<Object?> _templateItems(Object? templates) {
    if (templates is! List) return const [];
    final result = <Object?>[];
    for (final item in templates) {
      final template = BackupJson.map(item);
      if (template == null) continue;
      result.add({
        'name': BackupJson.text(template['name']) ?? '',
        'template': BackupJson.text(template['template']) ?? '',
      });
    }
    return result;
  }

  static List<Object?> _subscriptionItems(Object? subscriptions) {
    if (subscriptions is! List) return const [];
    final result = <Object?>[];
    for (final item in subscriptions) {
      final row = BackupJson.map(item);
      if (row == null) continue;
      final url = BackupJson.text(row['url']);
      if (url == null) continue;
      result.add({
        'url': url,
        'name': BackupJson.text(row['name']) ?? url,
        'kind': BackupJson.text(row['kind']) ?? 'domain',
        'scope': BackupJson.text(row['scope']) ?? 'dns',
        'sourceType': 'remote',
        'enabled': row['enabled'] != false,
        'groupName': BackupJson.text(row['groupName']),
        'mirrorTemplate': BackupJson.text(row['mirrorTemplate']),
        'mirrorFallback': row['mirrorFallback'] != false,
      });
    }
    return result;
  }

  /// Legacy has separate `customBlockRules`/`customAllowRules`; merge into `kind`.
  static List<Object?> _rules(Object? value, String kind) {
    if (value is! List) return const [];
    final result = <Object?>[];
    for (final item in value) {
      final rule = BackupJson.map(item);
      if (rule == null) continue;
      final pattern = BackupJson.text(rule['pattern']);
      if (pattern == null) continue;
      result.add({
        'pattern': pattern,
        'kind': kind,
        'important': rule['important'] == true,
        'appScope': BackupJson.text(rule['appScope']),
        'appInverted': rule['appInverted'] == true,
        'rawLine': BackupJson.text(rule['rawLine']),
        'enabled': rule['enabled'] != false,
      });
    }
    return result;
  }

  static List<Object?> _rewrites(Object? value, Set<String> types) {
    if (value is! List) return const [];
    final result = <Object?>[];
    for (final item in value) {
      final rule = BackupJson.map(item);
      if (rule == null) continue;
      final pattern = BackupJson.text(rule['pattern']);
      final targetValue = BackupJson.text(rule['targetValue']);
      if (pattern == null || targetValue == null) continue;
      result.add({
        'pattern': pattern,
        'targetType': BackupJson.text(rule['targetType']) ?? types.first,
        'targetValue': targetValue,
        'rawLine': BackupJson.text(rule['rawLine']),
        'enabled': rule['enabled'] != false,
      });
    }
    return result;
  }

  static List<Object?> _addressRules(Object? value) {
    if (value is! List) return const [];
    final result = <Object?>[];
    for (final item in value) {
      final rule = BackupJson.map(item);
      if (rule == null) continue;
      final pattern = BackupJson.text(rule['pattern']);
      if (pattern == null) continue;
      result.add({
        'pattern': pattern,
        'kind': BackupJson.text(rule['kind']) ?? 'block',
        'rawLine': BackupJson.text(rule['rawLine']),
        'enabled': rule['enabled'] != false,
      });
    }
    return result;
  }

  static Map<String, Object?> _appearance(Map<Object?, Object?> appearance) => {
    'themeMode': BackupJson.text(appearance['appThemeMode']),
    'palette': BackupJson.text(appearance['themeColorStyle']),
    'homePowerButtonOpacity': appearance['homePowerButtonOpacity'],
    'homeProviderSelectorOpacity': appearance['homeProviderSelectorOpacity'],
    'homeModeButtonOpacity': appearance['homeModeButtonOpacity'],
    'homePoemOpacity': appearance['homePoemOpacity'],
    'homeDnsDetailOpacity': appearance['homeDnsDetailOpacity'],
    'componentOpacity': appearance['homeComponentOpacity'],
    'homeSentenceRunning': BackupJson.text(appearance['homeSentenceRunning']),
    'homeSentenceStopped': BackupJson.text(appearance['homeSentenceStopped']),
  };

  static Map<String, Object?> _system(Map<Object?, Object?> system) => {
    'bypassLan': system['bypassLanEnabled'],
    'ipv6Mode': BackupJson.text(system['ipv6Mode']),
    'hideFromRecents': system['hideFromRecentsEnabled'],
    'logRetentionDays': BackupJson.integer(system['logRetentionDays']),
    'dnsLogMode': BackupJson.text(system['dnsLogMode']),
    'floatingLogEnabled': system['floatingLogEnabled'],
    'floatingLogPanelSize': BackupJson.integer(system['floatingLogPanelSize']),
    'appTrafficStatsEnabled': system['appTrafficStatsEnabled'],
    'trafficStatsRetentionDays': BackupJson.integer(
      system['trafficStatsRetentionDays'],
    ),
    'trafficStatsHideSystemApps': system['trafficStatsHideSystemApps'],
    'disableStartupUpdateCheck': system['disableStartupUpdateCheck'],
    'appLanguageMode': BackupJson.text(system['appLanguageMode']),
    'notificationPersistent': system['persistentNotificationEnabled'],
    'notificationSpeed': system['trafficSpeedEnabled'],
    'customRunningNotificationText': BackupJson.text(
      system['customRunningNotificationText'],
    ),
    'customStoppedNotificationText': BackupJson.text(
      system['customStoppedNotificationText'],
    ),
    'domainRulesEnabled': system['domainRulesEnabled'],
    'addressRulesEnabled': system['addressRulesEnabled'],
    'encryptedDnsBlockingEnabled': system['encryptedDnsBlockingEnabled'],
    'blockResponseMode': BackupJson.text(system['blockResponseMode']),
    'allowEditDefaultWhitelist': system['allowEditDefaultWhitelist'],
    'dynamicBlockResponse': BackupJson.map(system['dynamicBlockResponse']),
  };
}
