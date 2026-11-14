/// Real subscription data from the 1.4.3 Room tables; updates parse the body into rules tagged
/// `sub_<id>`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';

import 'dart:async';

import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_android/data/db/rule_dataset_providers.dart';
import 'package:diting_shared/data/native/platform_bridge.dart';
import 'package:diting_android/data/db/mirror_template_repository.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_android/data/rules/rule_importer.dart';
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
part 'subscription_update_providers.dart';

/// Subscriptions live in the active data set's rule database, which is why a mode switch reloads
/// this provider and every reader below it.
final subscriptionDatabaseFileProvider = Provider<String>(
  (ref) => ref.watch(activeRuleDatabaseProvider),
);

/// Null on a fresh install (no legacy file yet), giving an empty list.
final subscriptionDatabaseProvider = FutureProvider<Database?>(
  (ref) => LegacyDatabase.open(ref.watch(subscriptionDatabaseFileProvider)),
);

/// Bumped by every write so all subscription readers rebuild together.
class SubscriptionRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final subscriptionRevisionProvider =
    NotifierProvider<SubscriptionRevisionNotifier, int>(
      SubscriptionRevisionNotifier.new,
    );

/// Reads a local rule file back through its persisted SAF grant; null without a channel.
final subscriptionFileReaderProvider = Provider<PlatformBridge>(
  (ref) => PlatformBridge(),
);

/// Real fetcher; tests inject a fake with `overrideWithValue`. The UA comes from
/// `/config/user-agents`, the fallback mirror from the global mirror setting.
final subscriptionFetcherProvider = Provider<SubscriptionFetcher>((ref) {
  return HttpSubscriptionFetcher(
    userAgent: ref.watch(requestUserAgentProvider),
    globalMirrorTemplate: ref.watch(globalMirrorTemplateProvider),
  );
});

/// Rule importer sharing the repository handle; null without a database.
final ruleImporterProvider = FutureProvider<RuleImporter?>((ref) async {
  final db = await ref.watch(subscriptionDatabaseProvider.future);
  return db == null ? null : RuleImporter(db);
});

/// Subscription repository; null without a legacy database.
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

/// A subscription as rendered (model plus group name and derived labels).
class SubscriptionEntry {
  const SubscriptionEntry({required this.record, this.groupName});

  final SubscriptionRecord record;

  /// Resolved group name; null means ungrouped.
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

  /// Always false, since the parse chain is ported; kept so tests catch stale callers.
  bool get ruleCountIsLexicalOnly => false;

  bool get isRemote => record.isRemote;
  bool get isFailed => record.importState == SubscriptionImportState.failed;
  bool get isImporting =>
      record.importState == SubscriptionImportState.importing;

  /// R3 health, classified in Rust from the stored fields.
  SubscriptionHealth get health => record.health();

  /// Group chip key; a null group is shown as ungrouped.
  String get groupKey => groupName ?? ungroupedLabel;

  static String get ungroupedLabel => currentL10n.subscriptionUngrouped;
}

/// All subscriptions and groups; group names resolve from here.
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

/// Groups from `subscription_group`, ordered by `addedAt ASC, name NOCASE ASC`.
final subscriptionGroupsProvider =
    FutureProvider<List<SubscriptionGroupRecord>>((ref) async {
      ref.watch(subscriptionRevisionProvider);
      final repository = await ref.watch(subscriptionRepositoryProvider.future);
      return repository == null
          ? const <SubscriptionGroupRecord>[]
          : repository.groups();
    });

/// Selected group id; null means all groups.
class SubscriptionGroupFilterNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? groupId) => state = groupId;
}

final subscriptionGroupFilterProvider =
    NotifierProvider<SubscriptionGroupFilterNotifier, int?>(
      SubscriptionGroupFilterNotifier.new,
    );

/// Subscriptions in the selected group; filtering stays out of the page.
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

/// Result of adding a subscription; failures carry a readable reason.
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

  /// Adds a subscription. [sourceType] `local` stores a `content://` address picked through the
  /// system file picker instead of a download URL, and imports it from that file.
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
    // The kernel leaves the name null when only the localised label can fill it.
    fields['name'] ??= currentL10n.subscriptionLocalRuleFile;
    final record = SubscriptionRecord.fromRow(fields);
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    if (repository == null) {
      return AddSubscriptionFailure(
        currentL10n.subscriptionLegacyDatabaseMissing,
      );
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

  /// Master switch; also flips its source rows, since a rule is active only when both it and a
  /// source are enabled.
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

  /// Deletes rules first; the other order would leave ownerless rules blocking.
  Future<void> remove(int id) async {
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    final record = await repository?.byId(id);
    await (await _ref.read(ruleImporterProvider.future))
        ?.removeRulesBySource(subscriptionSourceTag(id));
    await repository?.deleteById(id);
    refreshRuleIndexesForCurrentMode(_ref);
    // Release the SAF grant a local subscription no longer needs.
    if (record != null && !record.isRemote) {
      await _ref
          .read(subscriptionFileReaderProvider)
          .releasePersistedText(record.url);
    }
  }

  /// Creates a group and returns its id, or the existing id on a name clash.
  Future<int?> createGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return (await _ref.read(subscriptionRepositoryProvider.future))
        ?.insertGroup(name: trimmed);
  }

  /// Renames a group; false when the name is empty or already taken by another group.
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

  /// Deletes a group and moves its subscriptions to ungrouped; the subscriptions and their
  /// rules stay, since a group only filters and batches them.
  Future<void> deleteGroup(int id) async {
    await (await _ref.read(subscriptionRepositoryProvider.future))
        ?.dissolveGroup(id);
  }
}

final subscriptionActionsProvider = Provider<SubscriptionActions>(
  SubscriptionActions.new,
);
