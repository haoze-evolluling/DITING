part of 'subscription_providers.dart';

/// Update progress and busy flags in one notifier, so they change in the same frame.
class SubscriptionUpdateState {
  const SubscriptionUpdateState({
    this.updatingIds = const {},
    this.updatingAll = false,
    this.progress = 0,
    this.lastMessage,
  });

  final Set<int> updatingIds;
  final bool updatingAll;

  /// 0..1, advanced by completed rows during update-all.
  final double progress;

  /// Summary of the last bulk update, e.g. "3 updated, 1 unchanged, 1 failed".
  final String? lastMessage;

  bool get isBusy => updatingAll || updatingIds.isNotEmpty;

  SubscriptionUpdateState copyWith({
    Set<int>? updatingIds,
    bool? updatingAll,
    double? progress,
    String? lastMessage,
    bool clearMessage = false,
  }) => SubscriptionUpdateState(
    updatingIds: updatingIds ?? this.updatingIds,
    updatingAll: updatingAll ?? this.updatingAll,
    progress: progress ?? this.progress,
    lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
  );
}

class SubscriptionUpdateNotifier extends Notifier<SubscriptionUpdateState> {
  @override
  SubscriptionUpdateState build() => const SubscriptionUpdateState();

  /// Updates one subscription; re-entry returns immediately. Reads a live snapshot, as `insert`
  /// leaves the cache stale.
  Future<SubscriptionFetchResult?> updateOne(int id) async {
    if (state.isBusy) {
      return null;
    }
    final entry = await _loadEntry(id);
    if (entry == null) {
      return null;
    }
    state = state.copyWith(updatingIds: {id}, clearMessage: true);
    final result = await _runOne(entry);
    if (!ref.mounted) {
      return result;
    }
    state = state.copyWith(
      updatingIds: const {},
      lastMessage: _summarize([result]),
    );
    return result;
  }

  /// Loads one entry with its group name straight from the database.
  Future<SubscriptionEntry?> _loadEntry(int id) async {
    final repository = await ref.read(subscriptionRepositoryProvider.future);
    if (repository == null) {
      return null;
    }
    final record = await repository.byId(id);
    if (record == null) {
      return null;
    }
    final groups = await repository.groups();
    final groupName = groups
        .where((group) => group.id == record.groupId)
        .map((group) => group.name)
        .firstOrNull;
    return SubscriptionEntry(record: record, groupName: groupName);
  }

  /// Updates all serially like upstream's single WorkManager queue.
  Future<void> updateAll(List<SubscriptionEntry> targets) async {
    if (state.isBusy || targets.isEmpty) {
      return;
    }
    state = state.copyWith(updatingAll: true, progress: 0, clearMessage: true);
    final results = <SubscriptionFetchResult>[];
    for (final (index, entry) in targets.indexed) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(updatingIds: {entry.id});
      results.add(await _runOne(entry));
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        updatingIds: const {},
        progress: (index + 1) / targets.length,
      );
    }
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      updatingAll: false,
      progress: 0,
      lastMessage: _summarize(results),
    );
  }

  /// Runs one update and records the result; exceptions become failures so the UI never stays busy.
  Future<SubscriptionFetchResult> _runOne(SubscriptionEntry entry) async {
    final repository = await ref.read(subscriptionRepositoryProvider.future);
    if (repository == null) {
      return SubscriptionFetchResult.failed(currentL10n.subscriptionDatabaseUnavailable);
    }
    if (!entry.isRemote) {
      return _runLocal(entry, repository);
    }
    await repository.setImportState(
      entry.id,
      SubscriptionImportState.importing,
    );
    final result = await ref
        .read(subscriptionFetcherProvider)
        .fetch(entry.record);
    final now = DateTime.now().millisecondsSinceEpoch;
    switch (result.outcome) {
      case SubscriptionFetchOutcome.notModified:
        await repository.markNotModified(
          entry.id,
          attemptedAt: now,
          etag: result.etag ?? entry.record.httpEtag,
          lastModified: result.lastModified ?? entry.record.httpLastModified,
        );
      case SubscriptionFetchOutcome.content:
        // Parse and import; the count is rows actually written.
        final imported = await _importContent(entry, result.content ?? '');
        if (imported == null) {
          // A download that cannot be stored must report failure, not "updated".
          await repository.markUpdateFailed(
            entry.id,
            error: currentL10n.subscriptionRuleDbUnavailable,
            attemptedAt: now,
          );
          return SubscriptionFetchResult.failed(currentL10n.subscriptionRuleDbUnavailable);
        }
        await repository.markImported(
          entry.id,
          ruleCount: imported.insertedCount,
          lastUpdated: now,
          etag: result.etag,
          lastModified: result.lastModified,
        );
      case SubscriptionFetchOutcome.failed:
        await repository.markUpdateFailed(
          entry.id,
          error: result.error ?? currentL10n.subscriptionUpdateFailed,
          attemptedAt: now,
        );
    }
    return result;
  }

  /// Re-imports a local rule file through its persisted SAF grant. The `url` column holds the
  /// `content://` address for local rows, mirroring the legacy `sourceRef`.
  Future<SubscriptionFetchResult> _runLocal(
    SubscriptionEntry entry,
    SubscriptionRepository repository,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final read = await ref
        .read(subscriptionFileReaderProvider)
        .readPersistedText(entry.url);
    if (!read.isOk) {
      final reason = read.error ?? currentL10n.subscriptionLocalFileUnreadable;
      await repository.markUpdateFailed(
        entry.id,
        error: reason,
        attemptedAt: now,
      );
      return SubscriptionFetchResult.failed(reason, requestedUrl: entry.url);
    }
    final imported = await _importContent(entry, read.text!);
    if (imported == null) {
      final reason = currentL10n.subscriptionLocalRuleDbUnavailable;
      await repository.markUpdateFailed(
        entry.id,
        error: reason,
        attemptedAt: now,
      );
      return SubscriptionFetchResult.failed(reason);
    }
    await repository.markImported(
      entry.id,
      ruleCount: imported.insertedCount,
      lastUpdated: now,
      // A local file has no ETag or Last-Modified to remember.
      etag: null,
      lastModified: null,
    );
    return SubscriptionFetchResult(
      outcome: SubscriptionFetchOutcome.content,
      content: read.text,
      requestedUrl: entry.url,
    );
  }

  /// Parses the body and rewrites the rule tables for `sub_<id>` only; null without a rule
  /// database.
  Future<RuleImportSummary?> _importContent(
    SubscriptionEntry entry,
    String content,
  ) async {
    final importer = await ref.read(ruleImporterProvider.future);
    if (importer == null) {
      return null;
    }
    final source = subscriptionSourceTag(entry.id);
    final parsed = parseCategorized(content);
    await importer.removeRulesBySource(source);
    try {
      if (parsed.isEmpty) {
        return const RuleImportSummary();
      }
      return await importer.import(
        parsed,
        source: source,
        kind: entry.kind.storageValue,
        enabled: entry.enabled,
      );
    } finally {
      refreshRuleIndexesForCurrentMode(ref);
    }
  }

  static String _summarize(List<SubscriptionFetchResult> results) {
    if (results.isEmpty) {
      return currentL10n.subscriptionNothingToUpdate;
    }
    final updated = results.where((result) => result.isSuccess).length;
    final unchanged = results.where((result) => result.isNotModified).length;
    final failed = results.where((result) => result.isFailure).length;
    final parts = <String>[
      if (updated > 0) currentL10n.subscriptionUpdatedCount(updated),
      if (unchanged > 0) currentL10n.subscriptionUnchangedCount(unchanged),
      if (failed > 0) currentL10n.subscriptionFailedCount(failed),
    ];
    return parts.isEmpty ? currentL10n.subscriptionNothingToUpdate : parts.join('，');
  }
}

final subscriptionUpdateProvider =
    NotifierProvider<SubscriptionUpdateNotifier, SubscriptionUpdateState>(
      SubscriptionUpdateNotifier.new,
    );
