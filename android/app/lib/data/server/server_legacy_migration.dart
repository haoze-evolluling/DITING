library;

import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/db/app_database.dart';
import 'package:diting_android/data/db/storage_contract.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/prefs/legacy_settings.dart';
import 'package:diting_android/data/server/server_client.dart';
import 'package:diting_android/data/server/server_dns_config.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const _configKey = 'server_config_json';
const _migratedKey = 'server_legacy_migrated';

/// 把旧服务器模式（独立 Rust 进程 + `files/server/server.db`）的数据搬到
/// 普通模式那套偏好与规则库。
///
/// 只迁移配置与订阅定义：配置文件原样转成新的 `ServerConfig` JSON，订阅写成
/// 规则库里的 `subscription` 行。旧查询日志按约定直接丢弃，旧数据库与镜像
/// 文件在迁移成功后删除。规则正文不迁移（旧格式已不再支持），下次订阅更新
/// 会重新导入。
Future<void> migrateLegacyServerData(LegacyPrefsStore store) async {
  if (store.read(LegacySettings.serverContainer, _migratedKey) == '1') return;
  try {
    final serverDir = await _legacyServerDir();
    final raw = await _readLegacyConfig(serverDir);
    if (raw != null) {
      final config = ServerConfig.fromJson(raw);
      store.putString(
        LegacySettings.serverContainer,
        _configKey,
        jsonEncode(config.toJson()),
      );
      await _migrateSubscriptions(config.filter.lists);
      await _cacheDnsConfig(config);
      _discardLegacyData(serverDir);
    }
    // 内核日志写入器只写已存在的库；提前建库让开机自启也能落日志。
    await AppDatabase.open(StorageContract.serverLogsDatabase);
    store.putString(LegacySettings.serverContainer, _migratedKey, '1');
  } catch (error) {
    debugPrint('legacy server migration failed: $error');
  }
}

Future<Directory> _legacyServerDir() async {
  final databases = await getDatabasesPath();
  final dataDir = Directory(databases).parent.path;
  return Directory(p.join(dataDir, 'files', 'server'));
}

Future<Map<String, Object?>?> _readLegacyConfig(Directory dir) async {
  final file = File(p.join(dir.path, 'config.json'));
  if (await file.exists()) {
    final decoded = _decode(await file.readAsString());
    if (decoded != null) return decoded;
  }
  final database = File(p.join(dir.path, 'server.db'));
  if (!await database.exists()) return null;
  Database? db;
  try {
    db = await openDatabase(database.path, readOnly: true);
    final rows = await db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['server_config'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decode(rows.first['value'] as String?);
  } on DatabaseException catch (error) {
    debugPrint('legacy server config unreadable: $error');
    return null;
  } finally {
    await db?.close();
  }
}

Map<String, Object?>? _decode(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

Future<void> _migrateSubscriptions(List<ServerFilterList> lists) async {
  if (lists.isEmpty) return;
  final db = await AppDatabase.open(StorageContract.serverRulesDatabase);
  if (db == null) return;
  try {
    final repository = SubscriptionRepository(db);
    for (final list in lists) {
      if (list.url.trim().isEmpty) continue;
      final groupId = list.group.trim().isEmpty
          ? null
          : await repository.insertGroup(name: list.group.trim());
      await repository.insert(
        SubscriptionRecord(
          id: 0,
          url: list.url.trim(),
          name: list.name.trim().isEmpty ? list.url.trim() : list.name.trim(),
          sourceType: list.isRemote
              ? SubscriptionSourceType.remote
              : SubscriptionSourceType.local,
          kind: list.isHosts ? SubscriptionKind.hosts : SubscriptionKind.domain,
          enabled: list.enabled,
          ruleCount: 0,
          lastUpdated: 0,
          addedAt: DateTime.now().millisecondsSinceEpoch,
          importState: SubscriptionImportState.ready,
          lastAttemptAt: 0,
          consecutiveFailureCount: 0,
          mirrorFallback: list.mirrorFallback,
          mirrorTemplate: list.mirrorTemplate.isEmpty
              ? null
              : list.mirrorTemplate,
          groupId: groupId,
        ),
      );
    }
  } finally {
    await db.close();
  }
}

/// 让开机自启不必等到用户手动启动过一次才有可用的内核配置。
Future<void> _cacheDnsConfig(ServerConfig config) async {
  try {
    await const MethodChannel(
      serverChannelName,
    ).invokeMethod<void>('cache_dns_config', {
      'dnsConfig': encodeServerDnsConfig(config),
    });
  } on MissingPluginException {
    // 非 Android 环境（测试、桌面）没有该通道。
  } on PlatformException catch (error) {
    debugPrint('legacy server dns config cache failed: ${error.message}');
  }
}

void _discardLegacyData(Directory dir) {
  for (final name in const [
    'server.db',
    'server.db-wal',
    'server.db-shm',
    'server.db-journal',
    'config.json',
    'server.log',
    'control.sock',
  ]) {
    final file = File(p.join(dir.path, name));
    if (file.existsSync()) file.deleteSync();
  }
  for (final name in const ['querylog', 'rules']) {
    final directory = Directory(p.join(dir.path, name));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
