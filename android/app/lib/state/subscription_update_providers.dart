part of 'subscription_providers.dart';

typedef LargeSubscriptionConfirmer =
    Future<bool> Function(SubscriptionEntry entry, int byteLength);

class SubscriptionUpdateState {
  const SubscriptionUpdateState({
    this.updatingIds = const {},
    this.updatingAll = false,
    this.progress = 0,
    this.lastMessage,
  });

  final Set<int> updatingIds;
  final bool updatingAll;

  final double progress;

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

  void _invalidateEntries() {
    if (!ref.mounted) {
      return;
    }
    ref.read(subscriptionRevisionProvider.notifier).bump();
  }

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
        if (await _skipLargeImport(entry, result.byteLength, confirmLarge, repository)) {
          return SubscriptionFetchResult.skipped(
            requestedUrl: entry.url,
            usedMirror: result.usedMirror,
            byteLength: result.byteLength,
          );
        }
        final imported = await _importContent(
          entry,
          bytes: result.bodyBytes,
          text: result.content,
        );
        if (imported == null) {
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
    final content = read.text!;
    if (await _skipLargeImport(entry, content.length, confirmLarge, repository)) {
      return SubscriptionFetchResult.skipped(
        requestedUrl: entry.url,
        byteLength: content.length,
      );
    }
    final imported = await _importContent(entry, text: content);
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

  Future<({RuleImportSummary summary, String hash})?> _importContent(
    SubscriptionEntry entry, {
    Uint8List? bytes,
    String? text,
  }) async {
    final importer = await ref.read(ruleImporterProvider.future);
    if (importer == null) {
      return null;
    }
    final source = subscriptionSourceTag(entry.id);
    final kind = entry.kind.storageValue;
    final enabled = entry.enabled;
    final stream = bytes != null
        ? streamParseCategorizedBytes(bytes)
        : streamParseCategorized(text ?? '');
    await importer.removeRulesBySource(source);
    var hashState = ruleSetHashSeed();
    var summary = const RuleImportSummary();
    final versionRules = <String>[];
    var collectVersion = true;
    var totalRules = 0;
    try {
      for (var chunk = stream.next(); chunk != null; chunk = stream.next()) {
        final lines = canonicalRules(chunk);
        hashState = ruleSetHashUpdate(hashState, lines);
        totalRules += lines.length;
        if (collectVersion) {
          if (totalRules > maxVersionSnapshotRules) {
            collectVersion = false;
            versionRules.clear();
          } else {
            versionRules.addAll(lines);
          }
        }
        if (!chunk.isEmpty) {
          summary = summary.merge(
            await importer.import(
              chunk,
              source: source,
              kind: kind,
              enabled: enabled,
            ),
          );
        }
      }
    } finally {
      stream.dispose();
      refreshRuleIndexesForCurrentMode(ref);
    }
    final hash = ruleSetHashHex(hashState);
    if (collectVersion) {
      await _recordVersion(entry, versionRules, hash, summary.insertedCount);
    } else {
      debugPrint(
        'rule version skipped for ${entry.url}: $totalRules rules over '
        '$maxVersionSnapshotRules',
      );
    }
    return (summary: summary, hash: hash);
  }

  static const int maxVersionSnapshotRules = 60000;

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
