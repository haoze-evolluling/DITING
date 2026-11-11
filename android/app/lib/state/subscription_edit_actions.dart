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
    final prepared = RustSubscriptionCore.instance.call({
      'op': 'prepare.edit',
      'existing': {
        'url': record.url,
        'name': record.name,
        'kind': record.kind.storageValue,
        'sourceType': record.sourceType.storageValue,
      },
      'name': name,
      'url': url,
      'kind': kind.storageValue,
      'groupId': groupId,
      'mirrorTemplate': mirrorTemplate,
      'mirrorFallback': mirrorFallback,
      'urlParts': uriParts(Uri.tryParse(url.trim())),
    });
    final error = prepared['error'] as String?;
    if (error != null) {
      return EditSubscriptionFailure(subscriptionFormErrorText(error));
    }
    final values = (prepared['values'] as Map).cast<String, Object?>();
    final updatedKind = SubscriptionKind.normalize(values['kind'] as String?);
    final existing = await repository.byUrlAndKind(
      values['url']! as String,
      updatedKind,
    );
    if (existing != null && existing.id != id) {
      return EditSubscriptionFailure(
        currentL10n.subscriptionAlreadyExistsNamed(
          record.isRemote
              ? currentL10n.subscriptionThisLink
              : currentL10n.subscriptionThisFile,
          updatedKind.displayName(currentL10n),
          existing.name,
        ),
      );
    }
    await repository.updateConfig(
      id,
      name: values['name']! as String,
      url: values['url']! as String,
      kind: updatedKind,
      groupId: (values['groupId'] as num?)?.toInt(),
      mirrorTemplate: values['mirrorTemplate'] as String?,
      mirrorFallback: values['mirrorFallback'] as bool? ?? true,
      resetValidators: values['resetValidators'] as bool? ?? false,
    );
    return EditSubscriptionOk(
      needsReimport: prepared['needsReimport'] as bool? ?? false,
    );
  }
}
