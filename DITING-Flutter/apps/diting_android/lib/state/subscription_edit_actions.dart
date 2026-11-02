part of 'subscription_providers.dart';

// Editing an existing subscription (name, address, kind, group, mirror).

/// Result of editing a subscription; [needsReimport] means the stored rules no longer match
/// the row (address or kind changed) and an update should run right away.
sealed class EditSubscriptionResult {
  const EditSubscriptionResult();
}

class EditSubscriptionOk extends EditSubscriptionResult {
  const EditSubscriptionOk({required this.needsReimport});
  final bool needsReimport;
}

class EditSubscriptionFailure extends EditSubscriptionResult {
  const EditSubscriptionFailure(this.message);
  final String message;
}

extension SubscriptionEditActions on SubscriptionActions {
  /// Saves edits to subscription [id]. Local rows keep their picked file, so [url] is ignored
  /// for them; the source type never changes.
  Future<EditSubscriptionResult> edit(
    int id, {
    required String name,
    required String url,
    required SubscriptionKind kind,
    int? groupId,
    String? mirrorTemplate,
    bool mirrorFallback = true,
  }) async {
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    final record = await repository?.byId(id);
    if (repository == null || record == null) {
      return EditSubscriptionFailure(currentL10n.subscriptionNotFound);
    }
    final isLocal = !record.isRemote;
    final trimmedUrl = isLocal ? record.url : url.trim();
    if (!isLocal) {
      final urlError = validateSubscriptionUrl(trimmedUrl);
      if (urlError != null) {
        return EditSubscriptionFailure(urlError);
      }
    }
    final existing = await repository.byUrlAndKind(trimmedUrl, kind);
    if (existing != null && existing.id != id) {
      return EditSubscriptionFailure(
        currentL10n.subscriptionAlreadyExistsNamed(
          isLocal
              ? currentL10n.subscriptionThisFile
              : currentL10n.subscriptionThisLink,
          kind.displayName(currentL10n),
          existing.name,
        ),
      );
    }
    String? normalizedMirror;
    try {
      normalizedMirror = isLocal
          ? null
          : normalizeMirrorTemplate(mirrorTemplate);
    } on FormatException catch (error) {
      return EditSubscriptionFailure(error.message);
    }
    final trimmedName = name.trim();
    final sourceChanged = trimmedUrl != record.url || kind != record.kind;
    await repository.updateConfig(
      id,
      name: trimmedName.isEmpty
          ? (isLocal ? record.name : extractNameFromUrl(trimmedUrl))
          : trimmedName,
      url: trimmedUrl,
      kind: kind,
      groupId: groupId,
      mirrorTemplate: normalizedMirror,
      mirrorFallback: mirrorFallback,
      resetValidators: sourceChanged,
    );
    return EditSubscriptionOk(needsReimport: sourceChanged);
  }
}
