part of 'subscription_providers.dart';

/// Asks the user whether to import a subscription body over [maxSubscriptionBytes]. Returns true to
/// proceed. Supplied by the UI so the notifier stays free of widget code; a null confirmer (e.g. a
/// background auto-update with no screen) means the import proceeds without asking.
typedef LargeSubscriptionConfirmer =
    Future<bool> Function(SubscriptionEntry entry, int byteLength);

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
  Future<SubscriptionFetchResult?> updateOne(
    int id, {
    LargeSubscriptionConfirmer? confirmLarge,
  }) async {
    if (state.isBusy) {
      return null;
    }
    final entry = await _loadEntry(id);
    if (entry == null) {
      return null;
    }
    state = state.copyWith(updatingIds: {id}, clearMessage: true);
    SubscriptionFetchResult? result;
    // The busy flags are cleared in a `finally`: an update that throws used to leave the card
    // spinning forever, and every entry point is disabled while busy, so only a restart helped.
    try {
      result = await _runSafely(entry, confirmLarge);
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          updatingIds: const {},
          lastMessage: result == null ? null : _summarize([result]),
        );
        _invalidateEntries();
      }
    }
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
  Future<void> updateAll(
    List<SubscriptionEntry> targets, {
    LargeSubscriptionConfirmer? confirmLarge,
  }) async {
    if (state.isBusy || targets.isEmpty) {
      return;
    }
    state = state.copyWith(updatingAll: true, progress: 0, clearMessage: true);
    final results = <SubscriptionFetchResult>[];
    try {
      for (final (index, entry) in targets.indexed) {
        if (!ref.mounted) {
          return;
        }
        state = state.copyWith(updatingIds: {entry.id});
        results.add(await _runSafely(entry, confirmLarge));
        if (!ref.mounted) {
          return;
        }
        state = state.copyWith(
          updatingIds: const {},
          progress: (index + 1) / targets.length,
        );
      }
    } finally {
      // Always settles, so a failure cannot strand the page at a frozen percentage.
      if (ref.mounted) {
        state = state.copyWith(
          updatingAll: false,
          updatingIds: const {},
          progress: 0,
          lastMessage: _summarize(results),
        );
        _invalidateEntries();
      }
    }
  }

  /// Reloads the list once the update settles. The repository reports every write, but a write
  /// that throws reports nothing, and the update must still leave the page showing what the
  /// database now holds.
  void _invalidateEntries() {
    if (!ref.mounted) {
      return;
    }
    ref.read(subscriptionRevisionProvider.notifier).bump();
  }

  /// `_runOne` with unexpected throws turned into failures: the user gets a failed row instead
  /// of a silent stall.
  Future<SubscriptionFetchResult> _runSafely(
    SubscriptionEntry entry,
    LargeSubscriptionConfirmer? confirmLarge,
  ) async {
    try {
      return await _runOne(entry, confirmLarge);
    } catch (error, stack) {
      debugPrint('subscription update failed for ${entry.url}: $error\n$stack');
      return SubscriptionFetchResult.failed(
        currentL10n.subscriptionUpdateFailed,
        requestedUrl: entry.url,
      );
    }
  }

  /// Runs one update and records the result; exceptions become failures so the UI never stays busy.
  Future<SubscriptionFetchResult> _runOne(
    SubscriptionEntry entry,
    LargeSubscriptionConfirmer? confirmLarge,
  ) async {
    final repository = await ref.read(subscriptionRepositoryProvider.future);
    if (repository == null) {
      return SubscriptionFetchResult.failed(currentL10n.subscriptionDatabaseUnavailable);
    }
    if (!entry.isRemote) {
      return _runLocal(entry, repository, confirmLarge);
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
        // The body is already downloaded (and streamed into the importer in chunks); before parsing
        // an oversized one, ask the user — importing it may slow the app down or cause other
        // problems. Declining leaves the previous rules untouched.
        if (await _skipLargeImport(entry, result.byteLength, confirmLarge, repository)) {
          return SubscriptionFetchResult.skipped(
            requestedUrl: entry.url,
            usedMirror: result.usedMirror,
            byteLength: result.byteLength,
          );
        }
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
          ruleCount: imported.summary.insertedCount,
          lastUpdated: now,
          etag: result.etag,
          lastModified: result.lastModified,
          ruleSetHash: imported.hash,
        );
      case SubscriptionFetchOutcome.failed:
        await repository.markUpdateFailed(
          entry.id,
          error: result.error ?? currentL10n.subscriptionUpdateFailed,
          attemptedAt: now,
        );
      case SubscriptionFetchOutcome.skipped:
        break;
    }
    return result;
  }

  /// Decides whether to skip a large import before parsing. Over [maxSubscriptionBytes] and with a
  /// confirmer present, it asks the user; a decline restores the row so it is not left stuck
  /// `importing`. A null confirmer (background auto-update, no screen) proceeds without asking.
  Future<bool> _skipLargeImport(
    SubscriptionEntry entry,
    int byteLength,
    LargeSubscriptionConfirmer? confirmLarge,
    SubscriptionRepository repository,
  ) async {
    if (byteLength <= maxSubscriptionBytes || confirmLarge == null) {
      return false;
    }
    final allowed = await confirmLarge(entry, byteLength);
    if (allowed) {
      return false;
    }
    final restore = entry.record.importState == SubscriptionImportState.importing
        ? SubscriptionImportState.ready
        : entry.record.importState;
    await repository.setImportState(entry.id, restore);
    return true;
  }

  /// Re-imports a local rule file through its persisted SAF grant. The `url` column holds the
  /// `content://` address for local rows, mirroring the legacy `sourceRef`.
  Future<SubscriptionFetchResult> _runLocal(
    SubscriptionEntry entry,
    SubscriptionRepository repository,
    LargeSubscriptionConfirmer? confirmLarge,
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
    // Local `.txt` is ASCII-heavy, so its length tracks byte size; the importer streams it in
    // chunks, so a large file imports without the old whole-document blow-up.
    final content = read.text!;
    if (await _skipLargeImport(entry, content.length, confirmLarge, repository)) {
      return SubscriptionFetchResult.skipped(
        requestedUrl: entry.url,
        byteLength: content.length,
      );
    }
    final imported = await _importContent(entry, content);
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
      ruleCount: imported.summary.insertedCount,
      lastUpdated: now,
      // A local file has no ETag or Last-Modified to remember.
      etag: null,
      lastModified: null,
      ruleSetHash: imported.hash,
    );
    return SubscriptionFetchResult(
      outcome: SubscriptionFetchOutcome.content,
      content: read.text,
      byteLength: content.length,
      requestedUrl: entry.url,
    );
  }

  /// Parses the body and rewrites the rule tables for `sub_<id>` only; null without a rule
  /// database. On success also records an R6 version snapshot and returns its content hash.
  Future<({RuleImportSummary summary, String hash})?> _importContent(
    SubscriptionEntry entry,
    String content,
  ) async {
    final importer = await ref.read(ruleImporterProvider.future);
    if (importer == null) {
      return null;
    }
    final source = subscriptionSourceTag(entry.id);
    final parsed = parseCategorized(content);
    final rules = canonicalRules(parsed);
    final hash = ruleSetHash(rules);
    await importer.removeRulesBySource(source);
    try {
      final summary = parsed.isEmpty
          ? const RuleImportSummary()
          : await importer.import(
              parsed,
              source: source,
              kind: entry.kind.storageValue,
              enabled: entry.enabled,
            );
      // The rules are written now, so the recorded snapshot matches what the engine will load.
      await _recordVersion(entry, rules, hash, summary.insertedCount);
      return (summary: summary, hash: hash);
    } finally {
      refreshRuleIndexesForCurrentMode(ref);
    }
  }

  /// Rule sets above this many lines skip the full-text version snapshot: writing the whole body a
  /// second time is exactly the duplication that made a large import exhaust memory, and the
  /// snapshot is only a best-effort rollback aid. The import itself still records its hash.
  static const int maxVersionSnapshotRules = 60000;

  /// Best-effort R6 snapshot; a version-history failure must never fail the import itself.
  Future<void> _recordVersion(
    SubscriptionEntry entry,
    List<String> rules,
    String hash,
    int ruleCount,
  ) async {
    if (rules.length > maxVersionSnapshotRules) {
      debugPrint(
        'rule version skipped for ${entry.url}: ${rules.length} rules over '
        '$maxVersionSnapshotRules',
      );
      return;
    }
    try {
      final repository = await ref.read(ruleVersionRepositoryProvider.future);
      await repository?.recordVersion(
        groupId: 'sub_${entry.id}',
        hash: hash,
        ruleCount: ruleCount,
        rules: rules,
      );
    } catch (error, stack) {
      debugPrint('rule version record failed for ${entry.url}: $error\n$stack');
    }
  }

  static String _summarize(List<SubscriptionFetchResult> results) {
    if (results.isEmpty) {
      return currentL10n.subscriptionNothingToUpdate;
    }
    final updated = results.where((result) => result.isSuccess).length;
    final unchanged = results.where((result) => result.isNotModified).length;
    final failed = results.where((result) => result.isFailure).length;
    final skipped = results.where((result) => result.isSkipped).length;
    final parts = <String>[
      if (updated > 0) currentL10n.subscriptionUpdatedCount(updated),
      if (unchanged > 0) currentL10n.subscriptionUnchangedCount(unchanged),
      if (skipped > 0) currentL10n.subscriptionSkippedCount(skipped),
      if (failed > 0) currentL10n.subscriptionFailedCount(failed),
    ];
    return parts.isEmpty ? currentL10n.subscriptionNothingToUpdate : parts.join('，');
  }
}

final subscriptionUpdateProvider =
    NotifierProvider<SubscriptionUpdateNotifier, SubscriptionUpdateState>(
      SubscriptionUpdateNotifier.new,
    );
