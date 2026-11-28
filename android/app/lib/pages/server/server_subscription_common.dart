library;

import 'dart:io';

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/db/app_database.dart';
import 'package:diting_android/data/db/datasets.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 其他模式（普通 / 简洁）已经导入的订阅，服务器模式可从它们复制。
class ServerImportEntry {
  const ServerImportEntry({required this.record, this.groupName});

  final SubscriptionRecord record;
  final String? groupName;

  String get key => '${record.kind.storageValue}|${record.url}';
  String get group => groupName ?? '';
}

final serverOtherModeSubscriptionsProvider =
    FutureProvider.family<List<ServerImportEntry>, DataSet>((
      ref,
      dataSet,
    ) async {
      final db = await AppDatabase.open(dataSet.ruleDatabase, create: false);
      if (db == null) {
        return const [];
      }
      final repository = SubscriptionRepository(db);
      final records = await repository.all();
      final groups = await repository.groups();
      final names = {for (final group in groups) group.id: group.name};
      return [
        for (final record in records)
          ServerImportEntry(record: record, groupName: names[record.groupId]),
      ];
    });

String serverDataSourceLabel(DataSet dataSet, AppL10n l10n) =>
    switch (dataSet) {
      DataSet.normal => l10n.workModeNormalTitle,
      DataSet.express => l10n.workModeExpressTitle,
      DataSet.server => l10n.workModeServerTitle,
    };

String serverListKindLabel(ServerFilterList list, AppL10n l10n) {
  if (list.isAllKinds) return l10n.subscriptionKindAll;
  return list.isHosts
      ? l10n.subscriptionKindHosts
      : l10n.subscriptionKindDomain;
}

String serverListSourceLabel(ServerFilterList list, AppL10n l10n) =>
    list.isRemote ? l10n.subscriptionSourceRemote : l10n.subscriptionSourceLocal;

String serverListGroupLabel(ServerFilterList list, AppL10n l10n) =>
    list.group.isEmpty ? l10n.subscriptionUngrouped : list.group;

String serverListSubtitle(ServerFilterList list, AppL10n l10n) => [
  serverListGroupLabel(list, l10n),
  serverListKindLabel(list, l10n),
  serverListSourceLabel(list, l10n),
].join(' · ');

String serverListDisplayTarget(ServerFilterList list) {
  if (list.isRemote) {
    return list.url;
  }
  final name = p.basename(list.url);
  return name.isEmpty ? list.url : name;
}

String serverListUpdatedLabel(ServerFilterList list, AppL10n l10n) {
  if (list.lastUpdated <= 0) {
    return l10n.subsNeverUpdated;
  }
  return formatServerTimestamp(list.lastUpdated);
}

String formatServerTimestamp(int epochMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

String serverRuleCountLabel(int count) {
  final digits = count.abs().toString();
  final buffer = StringBuffer(count < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 服务器进程以应用 UID 运行，把本地规则复制到数据库目录下的
/// `server_local` 后，Rust 端可以直接按路径读取。
Future<String> copyServerLocalRuleFile({
  required String id,
  required String text,
}) async {
  final root = Directory(p.join(await getDatabasesPath(), 'server_local'));
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  final file = File(p.join(root.path, '$id.txt'));
  await file.writeAsString(text);
  return file.path;
}

Future<void> removeServerLocalRuleFile(String path) async {
  if (path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // 文件可能已被系统清理，忽略即可。
  }
}

/// 同一订阅在创建 / 编辑时重置统计，避免展示上一次正文的旧结果。
ServerFilterList resetServerListMetrics(
  ServerFilterList list, {
  required String url,
  required String kind,
  required String sourceType,
  required String mirrorUrl,
}) {
  final changed =
      list.url != url ||
      list.kind != kind ||
      list.sourceType != sourceType ||
      list.mirrorUrl != mirrorUrl;
  if (!changed) {
    return list;
  }
  return list.copyWith(
    rulesCount: 0,
    lastUpdated: 0,
    lastStatus: '',
    lastError: '',
  );
}
