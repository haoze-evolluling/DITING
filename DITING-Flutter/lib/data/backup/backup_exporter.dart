/// Backup export: serializes the selected groups into one JSON document. Proxy credentials and the
/// CA private key are never exported.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'dart:convert';

import 'package:diting/data/backup/backup_models.dart';
import 'package:diting/data/backup/legacy_backup_writer.dart';
import 'package:diting/data/db/rule_repository.dart';
import 'package:diting/data/db/subscription_models.dart';
import 'package:diting/data/db/subscription_repository.dart';
import 'package:diting/data/mock_data.dart';
import 'package:diting/data/prefs/legacy_settings.dart';
import 'package:diting/data/vpn/dns_config_builder.dart';
import 'package:diting/data/vpn/provider_store.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

part 'backup_exporter_rules.dart';

class BackupExportSource {
  const BackupExportSource({
    required this.settings,
    required this.database,
    this.onSkip,
  });

  final LegacySettings settings;

  final Database? database;

  final void Function(String message)? onSkip;
}

class BackupExportResult {
  const BackupExportResult({
    required this.content,
    required this.fileName,
    required this.included,
    required this.counts,
    this.skipped = const [],
  });

  final String content;
  final String fileName;
  final List<BackupGroup> included;

  final Map<BackupGroup, int> counts;

  /// Entries that could not be read, reported rather than counted as zero.
  final List<String> skipped;

  int get totalItems => counts.values.fold(0, (sum, value) => sum + value);

  bool get isEmpty => totalItems == 0;
}

class BackupExporter {
  const BackupExporter();

  static const _encoder = JsonEncoder.withIndent('  ');

  /// Serializes [groups] only; all groups when null.
  Future<BackupExportResult> export(
    BackupExportSource source, {
    Set<BackupGroup>? groups,
  }) async {
    final selected = groups ?? BackupGroup.values.toSet();
    final data = <String, Object?>{};
    final counts = <BackupGroup, int>{};
    final skipped = <String>[];
    final included = <BackupGroup>[];
    // Shared per-run cache: the two rewrite groups split one table, so it is read once.
    final cache = <String, Object?>{};

    for (final group in BackupGroup.values) {
      if (!selected.contains(group)) continue;
      try {
        final value = await _valueOf(group, source, cache: cache);
        data[group.key] = value;
        counts[group] = _countOf(value);
        included.add(group);
      } catch (error) {
        // One failing group must not abort the backup; a partial backup beats none.
        debugPrint('backup export skipped ${group.key}: $error');
        skipped.add('${group.title(currentL10n)}：$error');
        source.onSkip?.call('${group.title(currentL10n)}：$error');
      }
    }

    final now = DateTime.now();
    final payload = <String, Object?>{
      'format': BackupFormat.magic,
      'version': BackupFormat.version,
      'exportedAt': now.millisecondsSinceEpoch,
      'selection': [for (final group in included) group.key],
      'data': data,
      // Legacy flat fields are written too, so both readers accept the file.
      ...LegacyBackupWriter.toLegacy(data, source.settings),
    };

    return BackupExportResult(
      content: _encoder.convert(payload),
      fileName:
          '${BackupFormat.fileNamePrefix}-${BackupFormat.stampOf(now)}.json',
      included: included,
      counts: counts,
      skipped: skipped,
    );
  }

  /// One group as JSON: a `Map` for structured config, a `List` for rules.
  Future<Object?> _valueOf(
    BackupGroup group,
    BackupExportSource source, {
    required Map<String, Object?> cache,
  }) async => switch (group) {
    BackupGroup.providers => _providers(source),
    BackupGroup.bootstrap => _bootstrap(source),
    BackupGroup.cache => _cache(source),
    BackupGroup.outbound => _outbound(source),
    BackupGroup.subscriptions => _subscriptions(source),
    BackupGroup.domainRules => _rules(source, group),
    BackupGroup.rewriteDomain => _rewriteRules(
      source,
      const {'IPv4', 'IPv6'},
      cache,
    ),
    BackupGroup.rewriteCname => _rewriteRules(source, const {'CNAME'}, cache),
    BackupGroup.addressRules => _addressRules(source),
    BackupGroup.excluded => _stringList(source.settings.excludedPackages),
    BackupGroup.blocked => {
      'enabled': source.settings.blockedAppsEnabled,
      'packages': _stringList(source.settings.blockedAppPackages),
    },
    BackupGroup.allowlist => {
      'enabled': source.settings.appAllowlistEnabled,
      'rules': {
        for (final entry in source.settings.appAllowlistRules.entries)
          entry.key: _stringList(entry.value),
      },
    },
    BackupGroup.httpInspection => {
      'enabled': source.settings.httpInspectionEnabled,
      'http3Enabled': source.settings.http3InspectionEnabled,
      'packages': _stringList(source.settings.httpInspectionPackages),
    },
    BackupGroup.appearance => _appearance(source),
    BackupGroup.system => _system(source),
  };

  Object? _providers(BackupExportSource source) {
    final settings = source.settings;
    final raw = settings.userProvidersJson;
    var items = const <Object?>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) items = decoded;
      } on FormatException {
        // Skip corrupt JSON rather than propagate the damage to a restore.
        throw BackupFormatException(
          currentL10n.backupErrProvidersInvalidJson,
        );
      }
    }
    return {'items': items, 'selection': _providerSelection(settings)};
  }

  /// Provider selection; references carry `name` and `protocol` so they resolve on another device.
  Map<String, Object?> _providerSelection(LegacySettings settings) {
    final catalog = _providerCatalog(settings);
    final selectedId = settings.selectedProviderId;
    return {
      'selectedProvider': _refOf(catalog, selectedId),
      'resolutionMode': settings.resolutionModeRaw,
      'presetDnsService': settings.presetDnsServiceRaw,
      'raceTestDomain': settings.raceTestDomain,
      'raceProviderRefs': _providerRefs(catalog, settings.raceProviderIds),
      'smartPredictionProviderRefs': _providerRefs(
        catalog,
        settings.smartPredictionProviderIds,
      ),
      'parallelRaceProviderRefs': _providerRefs(
        catalog,
        settings.parallelRaceProviderIds,
      ),
      'primaryBackupProviderRefs': _providerRefs(
        catalog,
        settings.primaryBackupProviderIds,
      ),
      'latencyTestProviderRefs': _providerRefs(
        catalog,
        settings.latencyTestProviderIds,
      ),
      'homeProviderVisibility': {
        'visibleProtocols': _stringList(settings.homeVisibleProtocols),
        'hiddenProviderRefs': _providerRefs(
          catalog,
          settings.homeHiddenProviderIds,
        ),
        'visibleProviderRefs': _providerRefs(
          catalog,
          settings.homeVisibleProviderIds,
        ),
      },
    };
  }

  Map<String, ({String name, String protocol})> _providerCatalog(
    LegacySettings settings,
  ) {
    final catalog = <String, ({String name, String protocol})>{};
    for (final provider in defaultDnsProviders(currentL10n)) {
      catalog[provider.id] = (
        name: provider.name,
        protocol: provider.protocol.storageValue,
      );
    }
    for (final record in readUserProviders(settings)) {
      catalog[record.id] = (
        name: record.name,
        protocol: record.protocol.storageValue,
      );
    }
    return catalog;
  }

  List<Object?> _providerRefs(
    Map<String, ({String name, String protocol})> catalog,
    Iterable<String> ids,
  ) => [for (final id in ids) _refOf(catalog, id)];

  Map<String, Object?> _refOf(
    Map<String, ({String name, String protocol})> catalog,
    String id,
  ) {
    final entry = catalog[id];
    return {
      'id': id,
      'name': entry?.name ?? id,
      'protocol': entry?.protocol ?? 'DOH',
      'isPreset': id.startsWith('preset_'),
    };
  }

  Object? _bootstrap(BackupExportSource source) {
    final custom = source.settings.bootstrapCustomJson;
    Object? parsed;
    if (custom != null && custom.trim().isNotEmpty) {
      try {
        parsed = jsonDecode(custom);
      } on FormatException {
        throw BackupFormatException(
          currentL10n.backupErrBootstrapInvalidJson,
        );
      }
    }
    return {
      'enabled': source.settings.bootstrapEnabled,
      'presetIds': source.settings.bootstrapPresetIds,
      'custom': parsed,
    };
  }

  Object? _cache(BackupExportSource source) {
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

  /// Outbound proxy: protocol, host, port and target app only; no credentials.
  Object? _outbound(BackupExportSource source) {
    final settings = source.settings;
    return {
      'enabled': settings.rawValue('outbound_proxy_enabled') == true,
      'protocol': settings.rawValue('outbound_proxy_protocol'),
      'host': settings.rawValue('outbound_proxy_host'),
      'port': settings.rawValue('outbound_proxy_port'),
      'proxyAppPackage': settings.rawValue('outbound_proxy_app'),
      // Written explicitly so their absence does not look like a lost field.
      'credentialsExcluded': true,
    };
  }

  Object? _appearance(BackupExportSource source) {
    final settings = source.settings;
    final sentences = settings.homeSentences;
    return {
      'themeMode': settings.themeModeRaw,
      'palette': settings.paletteRaw,
      'liquidGlassMode': settings.liquidGlassModeRaw,
      'bottomBarStyle': settings.bottomBarStyleRaw,
      'tabTransition': settings.tabTransitionRaw,
      'componentOpacity': _opacity(settings.componentOpacity),
      'hapticEnabled': settings.hapticEnabled,
      'bottomBarIds': settings.bottomBarIds,
      'customBackgroundEnabled': settings.customBackgroundEnabled,
      // One opacity slider now; per-widget keys are still written for older versions.
      'homePowerButtonOpacity': _opacity(
        settings.homeOpacity('home_power_button_opacity'),
      ),
      'homeProviderSelectorOpacity': _opacity(
        settings.homeOpacity('home_provider_selector_opacity'),
      ),
      'homeModeButtonOpacity': _opacity(
        settings.homeOpacity('home_mode_button_opacity'),
      ),
      'homePoemOpacity': _opacity(settings.homeOpacity('home_poem_opacity')),
      'homeDnsDetailOpacity': _opacity(
        settings.homeOpacity('home_dns_detail_opacity'),
      ),
      'homeSentenceRunning': sentences.running,
      'homeSentenceStopped': sentences.stopped,
      'customBackgroundUri': settings.customBackgroundUri,
    };
  }

  /// Rounds opacity to two decimals; Android stores it as a Java `float` (`0.8` reads back as
  /// `0.800000011920929`).
  double _opacity(double value) => (value * 100).roundToDouble() / 100;

  Object? _system(BackupExportSource source) {
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

  static int _countOf(Object? value) => switch (value) {
    null => 0,
    List() => value.length,
    Map() => value.length,
    _ => 1,
  };

  /// `Set<String>` to a sorted list; sorting makes equal backups byte-identical.
  static List<String> _stringList(Iterable<String> values) =>
      values.toList()..sort();
}
