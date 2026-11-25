part of 'subscription_providers.dart';

/// 普通模式与简洁模式各自使用独立的规则库，这里取「另一个模式」的数据集。
final otherModeDataSetProvider = Provider<DataSet>((ref) {
  final current = ref.watch(activeDataSetProvider);
  return current == DataSet.express ? DataSet.normal : DataSet.express;
});

/// 只读取另一个模式已经导入的订阅，不创建数据库。
final otherModeSubscriptionsProvider = FutureProvider<List<SubscriptionEntry>>((
  ref,
) async {
  final dataSet = ref.watch(otherModeDataSetProvider);
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
      SubscriptionEntry(record: record, groupName: names[record.groupId]),
  ];
});

String subscriptionEntryKey(SubscriptionRecord record) =>
    '${record.kind.storageValue}|${record.url}';

class ModeImportResult {
  const ModeImportResult({required this.ids, required this.skipped});

  final List<int> ids;
  final int skipped;
}

class SubscriptionModeImporter {
  const SubscriptionModeImporter(this._ref);

  final Ref _ref;

  /// 把另一个模式的订阅复制到当前模式，同名分组会自动创建。
  Future<ModeImportResult> importEntries(
    Iterable<SubscriptionEntry> entries,
  ) async {
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    if (repository == null) {
      throw StateError(currentL10n.subscriptionDatabaseMissing);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final ids = <int>[];
    var skipped = 0;
    for (final entry in entries) {
      final existing = await repository.byUrlAndKind(entry.url, entry.kind);
      if (existing != null) {
        skipped++;
        continue;
      }
      final groupName = entry.groupName;
      final groupId = groupName == null || groupName.isEmpty
          ? null
          : await repository.insertGroup(name: groupName);
      final record = entry.record;
      final id = await repository.insert(
        SubscriptionRecord(
          id: 0,
          url: record.url,
          name: record.name,
          sourceType: record.sourceType,
          kind: record.kind,
          enabled: record.enabled,
          ruleCount: 0,
          lastUpdated: 0,
          addedAt: now,
          importState: SubscriptionImportState.importing,
          lastAttemptAt: 0,
          consecutiveFailureCount: 0,
          mirrorFallback: record.mirrorFallback,
          mirrorTemplate: record.mirrorTemplate,
          groupId: groupId,
        ),
      );
      ids.add(id);
    }
    return ModeImportResult(ids: ids, skipped: skipped);
  }
}

final subscriptionModeImporterProvider = Provider<SubscriptionModeImporter>(
  SubscriptionModeImporter.new,
);
