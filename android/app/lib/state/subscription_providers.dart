library;

import 'package:diting_android/app/l10n/l10n.dart';

import 'dart:async';

import 'package:diting_android/data/db/app_database.dart';
import 'package:diting_android/data/db/datasets.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/db/rule_dataset_providers.dart';
import 'package:diting_android/data/native/platform_bridge.dart';
import 'package:diting_android/data/db/mirror_template_repository.dart';
import 'package:diting_android/data/db/rule_version_repository.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_android/data/rules/rule_importer.dart';
import 'package:diting_android/data/rules/rule_models.dart';
import 'package:diting_android/data/rules/rule_parser.dart';
import 'package:diting_android/data/subscriptions/rust_subscription_core.dart';
import 'package:diting_android/data/subscriptions/subscription_fetcher.dart';
import 'package:diting_android/data/subscriptions/subscription_url.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_android/state/global_mirror_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

part 'subscription_edit_actions.dart';
part 'subscription_mirror_providers.dart';
part 'subscription_mode_import.dart';
part 'subscription_update_providers.dart';

final subscriptionDatabaseFileProvider = Provider<String>(
  (ref) => ref.watch(activeRuleDatabaseProvider),
);

final subscriptionDatabaseProvider = FutureProvider<Database?>(
  (ref) => AppDatabase.open(ref.watch(subscriptionDatabaseFileProvider)),
);

class SubscriptionRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final subscriptionRevisionProvider =
    NotifierProvider<SubscriptionRevisionNotifier, int>(
      SubscriptionRevisionNotifier.new,
    );

final subscriptionFileReaderProvider = Provider<PlatformBridge>(
  (ref) => PlatformBridge(),
);

final subscriptionFetcherProvider = Provider<SubscriptionFetcher>((ref) {
  return HttpSubscriptionFetcher(
    userAgent: ref.watch(requestUserAgentProvider),
    globalMirrorTemplate: ref.watch(globalMirrorTemplateProvider),
  );
});

final ruleImporterProvider = FutureProvider<RuleImporter?>((ref) async {
  final db = await ref.watch(subscriptionDatabaseProvider.future);
  return db == null ? null : RuleImporter(db);
});

final subscriptionRepositoryProvider = FutureProvider<SubscriptionRepository?>((
  ref,
) async {
  final db = await ref.watch(subscriptionDatabaseProvider.future);
  if (db == null) {
    return null;
  }
  return SubscriptionRepository(
    db,
    onChanged: () => ref.read(subscriptionRevisionProvider.notifier).bump(),
  );
});

final ruleVersionRepositoryProvider = FutureProvider<RuleVersionRepository?>((
  ref,
) async {
  final db = await ref.watch(subscriptionDatabaseProvider.future);
  return db == null ? null : RuleVersionRepository(db);
});

class SubscriptionEntry {
  const SubscriptionEntry({required this.record, this.groupName});

  final SubscriptionRecord record;

  final String? groupName;

  int get id => record.id;
  String get name => record.name;
  String get url => record.url;
  bool get enabled => record.enabled;
  int get ruleCount => record.ruleCount;
  SubscriptionKind get kind => record.kind;
  SubscriptionSourceType get sourceType => record.sourceType;
  SubscriptionImportState get importState => record.importState;
  String? get importError => record.importError;
  int get consecutiveFailureCount => record.consecutiveFailureCount;
  int get lastUpdated => record.lastUpdated;
  int get lastAttemptAt => record.lastAttemptAt;

  bool get isRemote => record.isRemote;
  bool get isFailed => record.importState == SubscriptionImportState.failed;
  bool get isImporting =>
      record.importState == SubscriptionImportState.importing;

  SubscriptionHealth get health => record.health();

  String get groupKey => groupName ?? ungroupedLabel;

  static String get ungroupedLabel => currentL10n.subscriptionUngrouped;
}

final subscriptionEntriesProvider = FutureProvider<List<SubscriptionEntry>>((
  ref,
) async {
  ref.watch(subscriptionRevisionProvider);
  final repository = await ref.watch(subscriptionRepositoryProvider.future);
  if (repository == null) {
    return const [];
  }
  final records = await repository.all();
  final groups = await repository.groups();
  final names = {for (final group in groups) group.id: group.name};
  return [
    for (final record in records)
      SubscriptionEntry(record: record, groupName: names[record.groupId]),
  ];
});

final subscriptionGroupsProvider =
    FutureProvider<List<SubscriptionGroupRecord>>((ref) async {
      ref.watch(subscriptionRevisionProvider);
      final repository = await ref.watch(subscriptionRepositoryProvider.future);
      return repository == null
          ? const <SubscriptionGroupRecord>[]
          : repository.groups();
    });

class SubscriptionGroupFilterNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? groupId) => state = groupId;
}

final subscriptionGroupFilterProvider =
    NotifierProvider<SubscriptionGroupFilterNotifier, int?>(
      SubscriptionGroupFilterNotifier.new,
    );

final filteredSubscriptionsProvider = Provider<List<SubscriptionEntry>>((ref) {
  final groupId = ref.watch(subscriptionGroupFilterProvider);
  final entries = ref.watch(subscriptionEntriesProvider).value ?? const [];
  if (groupId == null) {
    return entries;
  }
  return [
    for (final entry in entries)
      if (entry.record.groupId == groupId) entry,
  ];
});

sealed class AddSubscriptionResult {
  const AddSubscriptionResult();
}

class AddSubscriptionOk extends AddSubscriptionResult {
  const AddSubscriptionOk(this.id);
  final int id;
}

class AddSubscriptionFailure extends AddSubscriptionResult {
  const AddSubscriptionFailure(this.message);
  final String message;
}

class SubscriptionActions {
  const SubscriptionActions(this._ref);

  final Ref _ref;

  Future<AddSubscriptionResult> add({
    required String name,
    required String url,
    required SubscriptionKind kind,
    int? groupId,
    String? mirrorTemplate,
    bool mirrorFallback = true,
    SubscriptionSourceType sourceType = SubscriptionSourceType.remote,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prepared = RustSubscriptionCore.instance.call({
      'op': 'prepare.add',
      'name': name,
      'url': url,
      'kind': kind.storageValue,
      'sourceType': sourceType.storageValue,
      'mirrorTemplate': mirrorTemplate,
      'mirrorFallback': mirrorFallback,
      'groupId': groupId,
      'nowMs': now,
      'urlParts': uriParts(Uri.tryParse(url.trim())),
    });
    final error = prepared['error'] as String?;
    if (error != null) {
      return AddSubscriptionFailure(subscriptionFormErrorText(error));
    }
    final fields = (prepared['record'] as Map).cast<String, Object?>();
    fields['name'] ??= currentL10n.subscriptionLocalRuleFile;
    final record = SubscriptionRecord.fromRow(fields);
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    if (repository == null) {
      return AddSubscriptionFailure(currentL10n.subscriptionDatabaseMissing);
    }
    final existing = await repository.byUrlAndKind(record.url, record.kind);
    if (existing != null) {
      return AddSubscriptionFailure(
        currentL10n.subscriptionAlreadyExistsNamed(
          sourceType == SubscriptionSourceType.local
              ? currentL10n.subscriptionThisFile
              : currentL10n.subscriptionThisLink,
          record.kind.displayName(currentL10n),
          existing.name,
        ),
      );
    }
    final id = await repository.insert(record);
    return AddSubscriptionOk(id);
  }

  Future<void> setEnabled(int id, bool enabled) async {
    await (await _ref.read(subscriptionRepositoryProvider.future))
        ?.setEnabled(id, enabled);
    await (await _ref.read(ruleImporterProvider.future))
        ?.setSourceEnabled(subscriptionSourceTag(id), enabled);
    refreshRuleIndexesForCurrentMode(_ref);
  }

  Future<void> rename(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await (await _ref.read(subscriptionRepositoryProvider.future))
        ?.setName(id, trimmed);
  }

  Future<void> remove(int id) async {
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    final record = await repository?.byId(id);
    final importer = await _ref.read(ruleImporterProvider.future);
    // 导入被中断时可能留下暂存来源，删除订阅时一并清理。
    await importer?.removeRulesBySource(subscriptionStagingTag(id));
    await importer?.removeRulesBySource(subscriptionSourceTag(id));
    await repository?.deleteById(id);
    refreshRuleIndexesForCurrentMode(_ref);
    if (record != null && !record.isRemote) {
      await _ref
          .read(subscriptionFileReaderProvider)
          .releasePersistedText(record.url);
    }
  }

  Future<int?> createGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return (await _ref.read(subscriptionRepositoryProvider.future))
        ?.insertGroup(name: trimmed);
  }

  Future<bool> renameGroup(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    if (repository == null) {
      return false;
    }
    final existing = await repository.groupByName(trimmed);
    if (existing != null && existing.id != id) {
      return false;
    }
    await repository.setGroupName(id, trimmed);
    return true;
  }

  Future<void> deleteGroup(int id) async {
    await (await _ref.read(subscriptionRepositoryProvider.future))
        ?.dissolveGroup(id);
  }
}

final subscriptionActionsProvider = Provider<SubscriptionActions>(
  SubscriptionActions.new,
);
