// ignore_for_file: prefer_initializing_formals
// False positive: fields are private `_xxx`, and Dart forbids named parameters starting with `_`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/cleanup/cleanup_models.dart';
import 'package:diting_android/data/cleanup/cleanup_plan.dart';
import 'package:diting_android/data/cleanup/cleanup_sql.dart';
import 'package:diting_android/data/db/rule_repository.dart';
import 'package:diting_android/data/native/ca_bridge.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_shared/data/native/platform_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

export 'cleanup_models.dart';

/// Runs every cleanup action, sharing the prefs store, database cache and channels.
class DataCleanupService {
  DataCleanupService({
    required LegacyPrefsStore prefs,
    required PlatformBridge platform,
    required OutboundProxyStore outboundProxy,
    required Future<Database?> Function(String fileName) openDatabase,
    required int appVersionCode,
    CaCertificateService? caCertificate,
    Future<String> Function()? loadPresetAsset,
  }) : _prefs = prefs,
       _platform = platform,
       _outboundProxy = outboundProxy,
       _appVersionCode = appVersionCode,
       _ca = caCertificate ?? const UnavailableCaCertificateService(),
       _loadPresetAsset = loadPresetAsset,
       _databases = CleanupDatabases(openDatabase);

  final LegacyPrefsStore _prefs;
  final PlatformBridge _platform;
  final OutboundProxyStore _outboundProxy;

  /// Seed marker version code; must match startup seeding. A lower value re-seeds on the next
  /// launch, a higher one skips upgrade seeds entirely.
  final int _appVersionCode;

  final CaCertificateService _ca;
  final Future<String> Function()? _loadPresetAsset;
  final CleanupDatabases _databases;
  LegacySettings get _settings => LegacySettings(_prefs);

  /// 0 without the channel; actions that also clear prefs must still run.
  Future<int> _platformCall(Future<int> Function() call) async {
    try {
      return await call();
    } catch (error) {
      debugPrint('cleanup: platform call degraded to 0 ($error)');
      return 0;
    }
  }

  CleanupPlan get _plan => CleanupPlan.instance;

  /// Never rethrows: the caller needs a reason after the confirmation dialog.
  Future<CleanupResult> run(CleanupAction action) async {
    try {
      return switch (action) {
        CleanupAction.logs => await _clearLogs(),
        CleanupAction.traffic => await _clearTraffic(),
        CleanupAction.crash => _result(
          action,
          await _platformCall(_platform.clearCrashLogs),
        ),
        CleanupAction.dnsCache => await _clearDnsCache(),
        CleanupAction.providerWeights => _resetWeights(
          action,
          _plan.providerWeightsKey,
        ),
        CleanupAction.bootstrapWeights => _resetWeights(
          action,
          _plan.bootstrapWeightsKey,
        ),
        CleanupAction.domainRules => await _clearDomainRules(),
        CleanupAction.addressRules => await _clearAddressRules(),
        CleanupAction.subscriptions => await _clearSubscriptions(),
        CleanupAction.appRules => _resetAppRules(),
        CleanupAction.outboundProxy => await _resetOutboundProxy(),
        CleanupAction.caCertificate => await _resetCaCertificate(),
        CleanupAction.downloadCache => _result(
          action,
          await _platformCall(_platform.clearUpdateCache),
        ),
        CleanupAction.customBackground => await _clearCustomBackground(),
        CleanupAction.settingsGuides => _resetSettingsGuides(),
        CleanupAction.allData => await _clearAllLocalData(),
      };
    } catch (error) {
      debugPrint('data cleanup failed: ${action.name} ($error)');
      return CleanupResult.failed(action, currentL10n.cleanupFailed('$error'));
    }
  }

  CleanupResult _result(CleanupAction action, int removed, {String? detail}) =>
      CleanupResult(action: action, removed: removed, detail: detail);

  /// Per-table tolerance: a missing table must not skip the others.
  Future<CleanupResult> _clearLogs() async {
    var removed = 0;
    for (final db in await _databases.runtimeDatabases()) {
      for (final table in _plan.logTables) {
        removed += await deleteAllRows(db, table);
      }
    }
    return _result(CleanupAction.logs, removed);
  }

  /// Main database only: the express and server databases lack `app_traffic_daily`.
  Future<CleanupResult> _clearTraffic() async {
    final db = await _databases.main;
    final removed = db == null
        ? 0
        : await deleteAllRows(db, _plan.trafficTable);
    return _result(CleanupAction.traffic, removed);
  }

  /// The engine keeps its own in-memory LRU, which is not cleared here.
  Future<CleanupResult> _clearDnsCache() async {
    var removed = 0;
    for (final db in await _databases.runtimeDatabases()) {
      removed += await deleteAllRows(db, _plan.dnsCacheTable);
    }
    return _result(CleanupAction.dnsCache, removed);
  }

  /// Each dataset keeps its own copy of the health samples.
  CleanupResult _resetWeights(CleanupAction action, String key) {
    var removed = 0;
    for (final container in _plan.weightContainers) {
      if (_removeKey(container, key)) removed++;
    }
    return _result(action, removed);
  }

  /// Clears rules, then re-seeds the preset whitelist; otherwise hosts that must stay reachable
  /// stay blocked.
  Future<CleanupResult> _clearDomainRules() async {
    final preset = await loadPresetEntries(load: _loadPresetAsset);
    var removed = 0;
    for (final db in await _databases.ruleDatabases()) {
      removed += await db.transaction<int>((txn) async {
        var count = 0;
        for (final pair in _plan.domainClearPairs) {
          count += await deleteAllRows(txn, pair.sourceTable);
          count += await deleteAllRows(txn, pair.table);
        }
        // Only IPv4/IPv6 rewrites here; CNAME rewrites belong to address rules.
        final rewriteWhere = _plan.domainRewriteWhere;
        count += await deleteRowsWhere(
          txn,
          _plan.domainRewriteSourceTable,
          'ruleId IN (SELECT id FROM ${_plan.domainRewriteTable} WHERE $rewriteWhere)',
        );
        count += await deleteRowsWhere(
          txn,
          _plan.domainRewriteTable,
          rewriteWhere,
        );
        for (final table in _plan.domainCosmeticTables) {
          count += await deleteAllRows(txn, table);
        }
        count += await deleteRowsWhere(
          txn,
          _plan.domainSubscriptionTable,
          _plan.domainSubscriptionWhere,
        );
        await resetSubscriptionImportState(
          txn,
          table: _plan.subscriptionResetTable,
          values: _plan.subscriptionResetValues,
        );
        await deleteOrphanAutoUpdateItems(
          txn,
          table: _plan.autoUpdateOrphanTable,
          where: _plan.autoUpdateOrphanWhere,
        );
        return count;
      });
      // Only the main dataset is re-seeded.
      if (_plan.seedPresetOnMain &&
          preset.isNotEmpty &&
          _databases.isMain(db)) {
        await RuleRepository(db).resetPresetWhitelist(preset);
        _settings.markDefaultWhitelistSeeded(_versionCodeOrFallback);
      }
    }
    return _result(CleanupAction.domainRules, removed);
  }

  /// Clears all `go_url_rule` rows and the CNAME half of `rewrite_rule`.
  Future<CleanupResult> _clearAddressRules() async {
    var removed = 0;
    for (final db in await _databases.ruleDatabases()) {
      removed += await db.transaction<int>((txn) async {
        var count = 0;
        for (final pair in _plan.addressClearPairs) {
          count += await deleteAllRows(txn, pair.sourceTable);
          count += await deleteAllRows(txn, pair.table);
        }
        final rewriteWhere = _plan.addressRewriteWhere;
        count += await deleteRowsWhere(
          txn,
          _plan.addressRewriteSourceTable,
          'ruleId IN (SELECT id FROM ${_plan.addressRewriteTable} WHERE $rewriteWhere)',
        );
        count += await deleteRowsWhere(
          txn,
          _plan.addressRewriteTable,
          rewriteWhere,
        );
        return count;
      });
    }
    return _result(CleanupAction.addressRules, removed);
  }

  Future<CleanupResult> _clearSubscriptions() async {
    var removed = 0;
    for (final db in await _databases.ruleDatabases()) {
      removed += await db.transaction<int>((txn) async {
        var count = 0;
        for (final table in _plan.subscriptionTables) {
          count += await deleteAllRows(txn, table);
        }
        // Subscription-owned rules use `sub_<id>` sources; `staging_sub_` is mid-import.
        for (final pair in _plan.subscriptionRulePairs) {
          count += await deleteRowsWhere(
            txn,
            pair.sourceTable,
            _plan.subscriptionSourceWhere,
          );
          count += await deleteOrphanRows(txn, pair.table, pair.sourceTable);
        }
        return count;
      });
    }
    return _result(CleanupAction.subscriptions, removed);
  }

  /// All app lists together, or the page and the engine disagree on what is allowed.
  CleanupResult _resetAppRules() {
    var removed = 0;
    final container = _plan.appRulesContainer;
    for (final key in _plan.appRuleKeys) {
      if (_removeKey(container, key)) removed++;
    }
    // Reset `https_inspection_ready` too, or the next tunnel start assumes the CA works.
    if (_prefs.read(container, _plan.httpsInspectionReadyKey) != null) {
      _settings.setHttpsInspectionReady(false);
      removed++;
    }
    return _result(CleanupAction.appRules, removed);
  }

  /// Credentials live in the AndroidKeyStore, so the reset goes through native.
  Future<CleanupResult> _resetOutboundProxy() async {
    await _outboundProxy.reset();
    return _result(
      CleanupAction.outboundProxy,
      1,
      detail: currentL10n.cleanupProxyRestored,
    );
  }

  /// `inspect(regenerate: true)` is the only call that deletes the CA files.
  Future<CleanupResult> _resetCaCertificate() async {
    await _ca.inspect(regenerate: true);
    _settings.setHttpsInspectionReady(false);
    return _result(
      CleanupAction.caCertificate,
      1,
      detail: currentL10n.cleanupCaNeedsReimport,
    );
  }

  /// Both halves must run, or stale files or a lying UI remain.
  Future<CleanupResult> _clearCustomBackground() async {
    var removed = await _platformCall(_platform.clearCustomBackgroundCache);
    for (final key in _plan.customBackgroundKeys) {
      if (_removeKey(_plan.customBackgroundContainer, key)) removed++;
    }
    return _result(CleanupAction.customBackground, removed);
  }

  /// Also clears the "do not remind" entries; there is no way to restore them.
  CleanupResult _resetSettingsGuides() {
    var removed = 0;
    for (final key in _plan.settingsGuideKeys) {
      if (_removeKey(_plan.settingsGuidesContainer, key)) removed++;
    }
    for (final key in _prefs.readAll(_plan.dismissedContainer).keys.toList()) {
      if (!key.startsWith(_plan.dismissedPrefix)) continue;
      if (_removeKey(_plan.dismissedContainer, key)) removed++;
    }
    return _result(CleanupAction.settingsGuides, removed);
  }

  /// Every action in order, summing counts; a failing step does not stop the rest.
  Future<CleanupResult> _clearAllLocalData() async {
    var removed = 0;
    for (final name in _plan.allDataOrder) {
      removed += (await run(CleanupAction.values.byName(name))).removed;
    }
    // Also clears mirror templates and the recognition members cache.
    final db = await _databases.main;
    if (db != null) {
      for (final table in _plan.allDataTables) {
        removed += await deleteAllRows(db, table);
      }
    }
    for (final entry in _plan.allDataPrefs) {
      if (_removeKey(entry.container, entry.key)) removed++;
    }
    return _result(CleanupAction.allData, removed);
  }

  /// A key holding its default value still counts as removed.
  bool _removeKey(String container, String key) {
    final existed = _prefs.read(container, key) != null;
    if (existed) _prefs.remove(container, key);
    return existed;
  }

  /// The stored install version wins over the value passed in.
  int get _versionCodeOrFallback {
    final raw = _prefs.read(LegacySettings.uiContainer, 'app_version_code');
    return raw is int && raw > 0 ? raw : _appVersionCode;
  }
}
