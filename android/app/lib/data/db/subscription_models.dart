/// Models for the legacy subscription tables; the `storageValue` strings are persisted verbatim, so
/// any case or spelling change makes legacy rows unreadable.
library;

import 'package:diting_shared/app/l10n/l10n.dart';

import 'package:diting_android/data/subscriptions/rust_subscription_core.dart';

/// Parses a page of rows through the native core (defaults and storage spellings live there).
List<Map<String, Object?>> _parseRows(
  String op,
  List<Map<String, Object?>> rows,
) {
  if (rows.isEmpty) return const [];
  final answer = RustSubscriptionCore.instance.call({'op': op, 'rows': rows});
  return [
    for (final item in answer['items'] as List? ?? const [])
      (item as Map).cast<String, Object?>(),
  ];
}

int _int(Object? value) => (value as num?)?.toInt() ?? 0;
String _str(Object? value) => value as String? ?? '';
String? _optStr(Object? value) => value as String?;
bool _bool(Object? value) => value as bool? ?? false;

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

  /// Builds a record from the native core's normalised fields (no defaults are applied here).
  factory SubscriptionRecord.fromParsed(Map<String, Object?> row) =>
      SubscriptionRecord(
        id: _int(row['id']),
        url: _str(row['url']),
        name: _str(row['name']),
        sourceType: SubscriptionSourceType.fromStorage(
          row['sourceType'] as String?,
        ),
        kind: row['kind'] == 'hosts'
            ? SubscriptionKind.hosts
            : SubscriptionKind.domain,
        enabled: _bool(row['enabled']),
        ruleCount: _int(row['ruleCount']),
        lastUpdated: _int(row['lastUpdated']),
        addedAt: _int(row['addedAt']),
        importState: SubscriptionImportState.fromStorage(
          row['importState'] as String?,
        ),
        importError: _optStr(row['importError']),
        httpEtag: _optStr(row['httpEtag']),
        httpLastModified: _optStr(row['httpLastModified']),
        ruleSetHash: _optStr(row['ruleSetHash']),
        lastAttemptAt: _int(row['lastAttemptAt']),
        consecutiveFailureCount: _int(row['consecutiveFailureCount']),
        mirrorTemplate: _optStr(row['mirrorTemplate']),
        mirrorFallback: _bool(row['mirrorFallback']),
        groupId: (row['groupId'] as num?)?.toInt(),
      );

  static SubscriptionRecord fromRow(Map<String, Object?> row) =>
      SubscriptionRecord.fromParsed(_parseRows('model.records', [row]).single);

  static List<SubscriptionRecord> parseAll(List<Map<String, Object?>> rows) => [
    for (final row in _parseRows('model.records', rows))
      SubscriptionRecord.fromParsed(row),
  ];
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

  static SubscriptionGroupRecord fromParsed(Map<String, Object?> row) =>
      SubscriptionGroupRecord(
        id: _int(row['id']),
        name: _str(row['name']),
        autoUpdateEnabled: _bool(row['autoUpdateEnabled']),
        addedAt: _int(row['addedAt']),
      );

  static SubscriptionGroupRecord fromRow(Map<String, Object?> row) =>
      fromParsed(_parseRows('model.groups', [row]).single);

  static List<SubscriptionGroupRecord> parseAll(
    List<Map<String, Object?>> rows,
  ) => [for (final row in _parseRows('model.groups', rows)) fromParsed(row)];
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

  static SubscriptionAutoUpdateItemRecord fromParsed(
    Map<String, Object?> row,
  ) => SubscriptionAutoUpdateItemRecord(
    batchId: _str(row['batchId']),
    subscriptionId: _int(row['subscriptionId']),
    status: SubscriptionAutoUpdateStatus.fromStorage(row['status'] as String?),
    changed: _bool(row['changed']),
    ruleCount: _int(row['ruleCount']),
  );

  static SubscriptionAutoUpdateItemRecord fromRow(Map<String, Object?> row) =>
      fromParsed(_parseRows('model.items', [row]).single);

  static List<SubscriptionAutoUpdateItemRecord> parseAll(
    List<Map<String, Object?>> rows,
  ) => [for (final row in _parseRows('model.items', rows)) fromParsed(row)];
}
