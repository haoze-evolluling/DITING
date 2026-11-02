/// Models for the legacy subscription tables; the `storageValue` strings are persisted verbatim, so
/// any case or spelling change makes legacy rows unreadable.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
enum SubscriptionSourceType {
  remote('remote'),
  local('local');

  const SubscriptionSourceType(this.storageValue);

  final String storageValue;

  String label(AppL10n l10n) => switch (this) {
    SubscriptionSourceType.remote => l10n.subscriptionSourceRemote,
    SubscriptionSourceType.local => l10n.subscriptionSourceLocal,
  };

  static SubscriptionSourceType fromStorage(String? value) =>
      value == local.storageValue ? local : remote;
}

/// A subscription carries exactly one rule type; [normalize] falls back to [domain].
enum SubscriptionKind {
  domain('domain'),
  hosts('hosts');

  const SubscriptionKind(this.storageValue);

  final String storageValue;

  String displayName(AppL10n l10n) => switch (this) {
    SubscriptionKind.domain => l10n.subscriptionKindDomain,
    SubscriptionKind.hosts => l10n.subscriptionKindHosts,
  };

  static SubscriptionKind normalize(String? value) =>
      value?.trim().toLowerCase() == hosts.storageValue ? hosts : domain;

  static bool isCanonical(String? value) =>
      value?.trim().toLowerCase() == domain.storageValue ||
      value?.trim().toLowerCase() == hosts.storageValue;
}

enum SubscriptionImportState {
  ready('ready'),
  importing('importing'),
  failed('failed');

  const SubscriptionImportState(this.storageValue);

  final String storageValue;

  static SubscriptionImportState fromStorage(String? value) => switch (value) {
    'importing' => importing,
    'failed' => failed,
    _ => ready,
  };
}

enum SubscriptionAutoUpdateStatus {
  pendingRetry('pending_retry'),
  success('success'),
  failed('failed');

  const SubscriptionAutoUpdateStatus(this.storageValue);

  final String storageValue;

  static SubscriptionAutoUpdateStatus fromStorage(String? value) =>
      switch (value) {
        'success' => success,
        'failed' => failed,
        _ => pendingRetry,
      };
}

/// One `subscription` row; flags are stored as INTEGER 0/1 and exposed as bool.
class SubscriptionRecord {
  const SubscriptionRecord({
    required this.id,
    required this.url,
    required this.name,
    required this.sourceType,
    required this.kind,
    required this.enabled,
    required this.ruleCount,
    required this.lastUpdated,
    required this.addedAt,
    required this.importState,
    required this.lastAttemptAt,
    required this.consecutiveFailureCount,
    required this.mirrorFallback,
    this.importError,
    this.httpEtag,
    this.httpLastModified,
    this.ruleSetHash,
    this.mirrorTemplate,
    this.groupId,
  });

  final int id;
  final String url;
  final String name;
  final SubscriptionSourceType sourceType;
  final SubscriptionKind kind;
  final bool enabled;

  final int ruleCount;

  /// Epoch milliseconds of the last successful import; 0 means never.
  final int lastUpdated;
  final int addedAt;
  final SubscriptionImportState importState;
  final String? importError;
  final String? httpEtag;
  final String? httpLastModified;
  final String? ruleSetHash;

  /// Epoch milliseconds of the last attempt, whatever its outcome.
  final int lastAttemptAt;

  /// Consecutive failures, reset on success or 304.
  final int consecutiveFailureCount;
  final String? mirrorTemplate;
  final bool mirrorFallback;
  final int? groupId;

  bool get isRemote => sourceType == SubscriptionSourceType.remote;

  static SubscriptionRecord fromRow(Map<String, Object?> row) =>
      SubscriptionRecord(
        id: (row['id'] as num?)?.toInt() ?? 0,
        url: row['url'] as String? ?? '',
        name: row['name'] as String? ?? '',
        sourceType: SubscriptionSourceType.fromStorage(
          row['sourceType'] as String?,
        ),
        kind: SubscriptionKind.normalize(row['kind'] as String?),
        enabled: _flag(row['enabled']) ?? true,
        ruleCount: (row['ruleCount'] as num?)?.toInt() ?? 0,
        lastUpdated: (row['lastUpdated'] as num?)?.toInt() ?? 0,
        addedAt: (row['addedAt'] as num?)?.toInt() ?? 0,
        importState: SubscriptionImportState.fromStorage(
          row['importState'] as String?,
        ),
        importError: row['importError'] as String?,
        httpEtag: row['httpEtag'] as String?,
        httpLastModified: row['httpLastModified'] as String?,
        ruleSetHash: row['ruleSetHash'] as String?,
        lastAttemptAt: (row['lastAttemptAt'] as num?)?.toInt() ?? 0,
        consecutiveFailureCount:
            (row['consecutiveFailureCount'] as num?)?.toInt() ?? 0,
        mirrorTemplate: row['mirrorTemplate'] as String?,
        mirrorFallback: _flag(row['mirrorFallback']) ?? true,
        groupId: (row['groupId'] as num?)?.toInt(),
      );

  static bool? _flag(Object? value) => switch (value) {
    final num number => number.toInt() != 0,
    final bool flag => flag,
    _ => null,
  };
}

class SubscriptionGroupRecord {
  const SubscriptionGroupRecord({
    required this.id,
    required this.name,
    required this.autoUpdateEnabled,
    required this.addedAt,
  });

  final int id;
  final String name;
  final bool autoUpdateEnabled;
  final int addedAt;

  static SubscriptionGroupRecord fromRow(Map<String, Object?> row) =>
      SubscriptionGroupRecord(
        id: (row['id'] as num?)?.toInt() ?? 0,
        name: row['name'] as String? ?? '',
        autoUpdateEnabled:
            SubscriptionRecord._flag(row['autoUpdateEnabled']) ?? true,
        addedAt: (row['addedAt'] as num?)?.toInt() ?? 0,
      );
}

class SubscriptionAutoUpdateItemRecord {
  const SubscriptionAutoUpdateItemRecord({
    required this.batchId,
    required this.subscriptionId,
    required this.status,
    required this.changed,
    required this.ruleCount,
  });

  final String batchId;
  final int subscriptionId;
  final SubscriptionAutoUpdateStatus status;
  final bool changed;
  final int ruleCount;

  static SubscriptionAutoUpdateItemRecord fromRow(Map<String, Object?> row) =>
      SubscriptionAutoUpdateItemRecord(
        batchId: row['batchId'] as String? ?? '',
        subscriptionId: (row['subscriptionId'] as num?)?.toInt() ?? 0,
        status: SubscriptionAutoUpdateStatus.fromStorage(
          row['status'] as String?,
        ),
        changed: (row['changed'] as num?)?.toInt() == 1,
        ruleCount: (row['ruleCount'] as num?)?.toInt() ?? 0,
      );
}
