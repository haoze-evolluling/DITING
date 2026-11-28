library;

import 'dart:async';
import 'dart:convert';

import 'package:diting_android/data/db/app_database.dart';
import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/storage_contract.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_android/data/rules/rule_importer.dart';
import 'package:diting_android/data/rules/rule_parser.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/server/server_client.dart';
import 'package:diting_android/data/server/server_dns_config.dart';
import 'package:diting_android/data/server/server_launch_models.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/state/rule_test_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

const _configKey = 'server_config_json';
const _customRuleSource = 'useradd';

/// 服务器模式的客户端。
///
/// 运行状态来自进程内内核；配置保存在服务器模式自己的偏好容器里；统计与
/// 查询日志直接读服务器模式的日志库，与普通/简洁模式共用同一套表结构。
class SharedServerClient implements ServerClient {
  SharedServerClient(
    this._ref, {
    MethodChannel? channel,
    EventChannel? statusChannel,
  }) : _channel = channel ?? const MethodChannel(serverChannelName),
       _statusChannel =
           statusChannel ?? const EventChannel(serverStatusChannelName);

  final Ref _ref;
  final MethodChannel _channel;
  final EventChannel _statusChannel;

  LegacyPrefsStore get _store => _ref.read(legacyPrefsStoreProvider);

  Future<Object?> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      throw const ServerException('服务器模式仅在 Android 上可用');
    } on PlatformException catch (error) {
      throw ServerException(error.message ?? error.code);
    }
  }

  @override
  Future<ServerStatus> status() async =>
      ServerStatus.fromMap(await _invoke('status'));

  @override
  Stream<ServerStatus> watchStatus() {
    try {
      return _statusChannel
          .receiveBroadcastStream()
          .map(ServerStatus.fromMap)
          .handleError((Object _) {});
    } on MissingPluginException {
      return const Stream.empty();
    }
  }

  @override
  Future<bool> start({required bool preferRoot}) async {
    final config = await getConfig();
    // 内核的日志写入器只往已存在的库里写，先建库避免启动初期的日志被丢弃。
    await AppDatabase.open(StorageContract.serverLogsDatabase);
    await _syncCustomRules(config);
    return await _invoke('start', {
          'preferRoot': preferRoot,
          'dnsConfig': encodeServerDnsConfig(config),
        }) ==
        true;
  }

  @override
  Future<bool> stop() async => await _invoke('stop') == true;

  @override
  Future<ServerRootStatus> probeRoot() async =>
      ServerRootStatus.fromMap(await _invoke('probe_root'));

  @override
  Future<ServerLaunchSettings> getLaunchSettings() async =>
      ServerLaunchSettings.fromMap(await _invoke('launch_settings'));

  @override
  Future<void> saveLaunchSettings(ServerLaunchSettings settings) async {
    await _invoke('set_launch_settings', {
      'autoStart': settings.autoStart,
      'autoRestart': settings.autoRestart,
    });
  }

  @override
  Future<String?> readConfig() async {
    final raw = _store.read(LegacySettings.serverContainer, _configKey);
    return raw is String ? raw : null;
  }

  @override
  Future<void> writeConfig(ServerConfig config) async {
    _store.putString(
      LegacySettings.serverContainer,
      _configKey,
      jsonEncode(config.toJson()),
    );
  }

  @override
  Future<ServerConfig> getConfig() async {
    final raw = await readConfig();
    final base = raw == null || raw.trim().isEmpty
        ? ServerConfig.defaults()
        : _decodeConfig(raw);
    return _withSubscriptions(base);
  }

  ServerConfig _decodeConfig(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const ServerException('服务器配置格式错误');
    return ServerConfig.fromJson(Map<String, Object?>.from(decoded));
  }

  /// 订阅以规则库为唯一真源；配置里的 `filter.lists` 只作为只读投影供界面展示。
  Future<ServerConfig> _withSubscriptions(ServerConfig config) async {
    final db = await _openRules();
    if (db == null) return config;
    try {
      final repository = SubscriptionRepository(db);
      final records = await repository.all();
      if (records.isEmpty && config.filter.lists.isEmpty) return config;
      final groups = {
        for (final group in await repository.groups()) group.id: group.name,
      };
      return config.copyWith(
        filter: config.filter.copyWith(
          lists: [
            for (final record in records)
              ServerFilterList(
                id: '${record.id}',
                name: record.name,
                url: record.url,
                enabled: record.enabled,
                rulesCount: record.ruleCount,
                lastUpdated: record.lastUpdated,
                lastStatus: record.importState.storageValue,
                lastError: record.importError ?? '',
                group: groups[record.groupId] ?? '',
                kind: record.kind.storageValue,
                sourceType: record.sourceType.storageValue,
                mirrorTemplate: record.mirrorTemplate ?? '',
                mirrorFallback: record.mirrorFallback,
              ),
          ],
        ),
      );
    } finally {
      await db.close();
    }
  }

  Future<Database?> _openRules() =>
      AppDatabase.open(StorageContract.serverRulesDatabase, create: false);

  @override
  Future<ServerConfig> saveConfig(ServerConfig config) async {
    final previous = await getConfig();
    await writeConfig(config);
    if (previous.filter.customRules.join('\n') !=
        config.filter.customRules.join('\n')) {
      await _syncCustomRules(config);
    }
    if ((await status()).running) {
      await _invoke('apply_dns_config', {
        'dnsConfig': encodeServerDnsConfig(config),
      });
      if (previous.filter.customRules.join('\n') !=
          config.filter.customRules.join('\n')) {
        await _invoke('reload_rules');
      }
    }
    return config;
  }

  /// 自定义规则和普通模式一样编译进规则库，交给内核统一匹配。
  Future<void> _syncCustomRules(ServerConfig config) async {
    final db = await AppDatabase.open(StorageContract.serverRulesDatabase);
    if (db == null) return;
    try {
      final importer = RuleImporter(db);
      await importer.removeRulesBySource(_customRuleSource);
      final text = config.filter.customRules.join('\n');
      if (text.trim().isEmpty) return;
      final parsed = parseCategorized(text);
      if (parsed.isEmpty) return;
      await importer.import(
        parsed,
        source: _customRuleSource,
        kind: 'domain',
        enabled: true,
      );
    } on Object catch (error) {
      debugPrint('server custom rules sync failed: $error');
    } finally {
      await db.close();
    }
  }

  @override
  Future<ServerStats> stats() async {
    final db = await _openLogs();
    if (db == null) return const ServerStats();
    final since = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    final summary = await db.rawQuery(
      '''
SELECT COUNT(*) AS queries,
       SUM(CASE WHEN result = 'BLOCKED' THEN 1 ELSE 0 END) AS blocked,
       SUM(CASE WHEN cached = 1 THEN 1 ELSE 0 END) AS cached,
       SUM(CASE WHEN result = 'ERROR' THEN 1 ELSE 0 END) AS errors,
       AVG(durationMs) AS average
FROM dns_log WHERE timestamp >= ?
''',
      [since],
    );
    final row = summary.first;
    final queries = _int(row['queries']);
    final blocked = _int(row['blocked']);
    final cached = _int(row['cached']);
    final errors = _int(row['errors']);

    final perHour = await db.rawQuery(
      '''
SELECT (timestamp / 3600000) * 3600000 AS hourMs,
       COUNT(*) AS queries,
       SUM(CASE WHEN result = 'BLOCKED' THEN 1 ELSE 0 END) AS blocked,
       SUM(CASE WHEN cached = 1 THEN 1 ELSE 0 END) AS cached
FROM dns_log WHERE timestamp >= ?
GROUP BY hourMs ORDER BY hourMs
''',
      [since],
    );
    final topDomains = await _rank(
      db,
      queryNameColumn: 'queryName',
      where: 'timestamp >= ?',
      args: [since],
    );
    final topBlocked = await _rank(
      db,
      queryNameColumn: 'queryName',
      where: "timestamp >= ? AND result = 'BLOCKED'",
      args: [since],
    );
    final topClients = await _rank(
      db,
      queryNameColumn: 'clientIp',
      where: "timestamp >= ? AND clientIp <> ''",
      args: [since],
    );
    return ServerStats(
      queries: queries,
      blocked: blocked,
      cached: cached,
      forwarded: (queries - cached).clamp(0, queries),
      errors: errors,
      averageResponseMs: _double(row['average']),
      blockedRate: queries == 0 ? 0 : blocked / queries,
      cacheHitRate: queries == 0 ? 0 : cached / queries,
      perHour: [
        for (final item in perHour)
          ServerHourPoint(
            hour: DateTime.fromMillisecondsSinceEpoch(_int(item['hourMs'])),
            queries: _int(item['queries']),
            blocked: _int(item['blocked']),
            cached: _int(item['cached']),
          ),
      ],
      topDomains: topDomains,
      topBlockedDomains: topBlocked,
      topClients: topClients,
    );
  }

  Future<List<ServerNameCount>> _rank(
    Database db, {
    required String queryNameColumn,
    required String where,
    required List<Object?> args,
  }) async {
    final rows = await db.rawQuery(
      'SELECT $queryNameColumn AS name, COUNT(*) AS count FROM dns_log '
      'WHERE $where GROUP BY $queryNameColumn ORDER BY count DESC LIMIT 10',
      args,
    );
    return [
      for (final row in rows)
        ServerNameCount(
          name: row['name'] as String? ?? '',
          count: _int(row['count']),
        ),
    ];
  }

  @override
  Future<ServerQueryResult> queryLog(ServerLogQuery query) async {
    final db = await _openLogs();
    if (db == null) return const ServerQueryResult();
    final (where, args) = _whereOf(query);
    final total = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM dns_log WHERE $where',
      args,
    );
    final rows = await db.rawQuery(
      'SELECT * FROM dns_log WHERE $where '
      'ORDER BY timestamp DESC, id DESC LIMIT ? OFFSET ?',
      [...args, query.limit, query.offset],
    );
    return ServerQueryResult(
      total: _int(total.first['n']),
      entries: [for (final row in rows) _recordOf(row)],
    );
  }

  (String, List<Object?>) _whereOf(ServerLogQuery query) {
    final clauses = <String>['1 = 1'];
    final args = <Object?>[];
    if (query.domain.isNotEmpty) {
      clauses.add('queryName LIKE ?');
      args.add('%${query.domain}%');
    }
    if (query.client.isNotEmpty) {
      clauses.add('(clientIp LIKE ? OR clientName LIKE ?)');
      args
        ..add('%${query.client}%')
        ..add('%${query.client}%');
    }
    switch (query.status) {
      case 'blocked':
        clauses.add("result = 'BLOCKED'");
      case 'error':
        clauses.add("result = 'ERROR'");
      case 'cached':
        clauses.add('cached = 1');
      case 'allowed':
        clauses.add("result <> 'BLOCKED' AND result <> 'ERROR'");
      default:
        break;
    }
    final type = _qtypeValue(query.qtype);
    if (type != null) {
      clauses.add('queryType = ?');
      args.add(type);
    }
    if (query.rcode.isNotEmpty) {
      clauses.add('rcode = ?');
      args.add(query.rcode);
    }
    if (query.startMs > 0) {
      clauses.add('timestamp >= ?');
      args.add(query.startMs);
    }
    if (query.endMs > 0) {
      clauses.add('timestamp <= ?');
      args.add(query.endMs);
    }
    return (clauses.join(' AND '), args);
  }

  ServerQueryRecord _recordOf(Map<String, Object?> row) {
    final result = row['result'] as String? ?? 'PASSED';
    final cached = _int(row['cached']) == 1;
    final message = row['message'] as String?;
    final fields = DnsLogMessage.parse(message);
    final hasError = result == 'ERROR';
    final status = hasError
        ? 'error'
        : result == 'BLOCKED'
        ? 'blocked'
        : cached
        ? 'cached'
        : 'allowed';
    final queryType = _int(row['queryType']);
    return ServerQueryRecord(
      timestamp: DateTime.fromMillisecondsSinceEpoch(_int(row['timestamp'])),
      domain: row['queryName'] as String? ?? '',
      qtype: _qtypeName(queryType),
      clientIP: row['clientIp'] as String? ?? '',
      clientName: row['clientName'] as String? ?? '',
      durationMs: _double(row['durationMs']),
      rcode: row['rcode'] as String? ?? '',
      status: status,
      cached: cached,
      ttl: row['ttl'] == null ? null : _int(row['ttl']),
      cacheHit: row['cacheHit'] as String? ?? '',
      blocked: result == 'BLOCKED',
      filterRule: fields.blockedBy ?? '',
      filterReason: hasError ? fields.error ?? (message ?? '') : '',
      protocol: row['protocol'] as String? ?? '',
      upstreamProvider: row['upstreamProvider'] as String? ?? '',
      error: hasError ? fields.error ?? (message ?? '') : '',
    );
  }

  @override
  Future<void> clearQueryLog() async {
    final db = await _openLogs();
    await db?.delete('dns_log');
  }

  @override
  Future<void> clearCache() async {
    await _invoke('clear_cache');
  }

  @override
  Future<ServerFilterConfig> refreshFilter([String id = '']) async {
    await _invoke('reload_rules');
    final config = await getConfig();
    return config.filter;
  }

  @override
  Future<ServerFilterCheck> filterCheck(
    String domain, {
    String qtype = 'A',
  }) async {
    final result = await _ref.read(ruleTestBridgeProvider).check(
      domain: domain,
      qtype: _qtypeValue(qtype) ?? 1,
      dataset: 'server',
    );
    return ServerFilterCheck(
      blocked: result.blocked,
      action: result.action.name,
      matchedRule: result.matchedRule ?? '',
      reason: result.reason,
    );
  }

  Future<Database?> _openLogs() =>
      AppDatabase.open(StorageContract.serverLogsDatabase);
}

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

double _double(Object? value) => (value as num?)?.toDouble() ?? 0;

int? _qtypeValue(String name) => switch (name.toUpperCase()) {
  'A' => 1,
  'NS' => 2,
  'CNAME' => 5,
  'SOA' => 6,
  'PTR' => 12,
  'MX' => 15,
  'TXT' => 16,
  'AAAA' => 28,
  'SRV' => 33,
  'HTTPS' => 65,
  'SVCB' => 64,
  _ => int.tryParse(name),
};

String _qtypeName(int value) => switch (value) {
  1 => 'A',
  2 => 'NS',
  5 => 'CNAME',
  6 => 'SOA',
  12 => 'PTR',
  15 => 'MX',
  16 => 'TXT',
  28 => 'AAAA',
  33 => 'SRV',
  65 => 'HTTPS',
  64 => 'SVCB',
  _ => '$value',
};
