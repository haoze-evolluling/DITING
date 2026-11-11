/// Backup export: the Rust core writes the document, this file only hands it a snapshot of what
/// the app currently holds (settings getters plus the four tables it may export).
library;

import 'package:diting_shared/app/l10n/l10n.dart';

import 'package:diting_android/data/backup/backup_models.dart';
import 'package:diting_android/data/backup/rust_backup_core.dart';
import 'package:diting_android/data/db/rule_repository.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/data/vpn/provider_store.dart';
import 'package:sqflite/sqflite.dart';

part 'backup_export_snapshot.dart';

class BackupExportSource {
  const BackupExportSource({
    required this.settings,
    required this.database,
    this.onSkip,
  });

  final LegacySettings settings;

  final Database? database;

  final void Function(String message)? onSkip;
}

class BackupExportResult {
  const BackupExportResult({
    required this.content,
    required this.fileName,
    required this.included,
    required this.counts,
    this.skipped = const [],
  });

  /// The whole document. Empty for a streamed export ([BackupExporter.exportTo]): the JSON went to
  /// the sink instead of being kept in memory.
  final String content;
  final String fileName;
  final List<BackupGroup> included;

  final Map<BackupGroup, int> counts;

  /// Entries that could not be read, reported rather than counted as zero.
  final List<String> skipped;

  int get totalItems => counts.values.fold(0, (sum, value) => sum + value);

  bool get isEmpty => totalItems == 0;

  BackupExportResult withContent(String content) => BackupExportResult(
    content: content,
    fileName: fileName,
    included: included,
    counts: counts,
    skipped: skipped,
  );
}

/// Receives the document as it is produced. Each call carries one piece of the file, so a caller
/// that uploads can start before the whole document has been handed over.
typedef BackupChunkSink = Future<void> Function(String chunk);

class BackupExporter {
  const BackupExporter();

  /// Chunk size for [exportTo]: the document is one string by the time the core returns it, so this
  /// only bounds how much a caller holds between awaits.
  static const _chunkBytes = 64 * 1024;

  /// The whole document as one string, for the WebDAV upload and the tests.
  Future<BackupExportResult> export(
    BackupExportSource source, {
    Set<BackupGroup>? groups,
  }) async {
    final buffer = StringBuffer();
    final result = await exportTo(
      (chunk) async => buffer.write(chunk),
      source,
      groups: groups,
    );
    return result.withContent(buffer.toString());
  }

  /// Streams [groups] only (all groups when null) to [sink].
  ///
  /// Every decision — which groups land in the file, what a group looks like, what is counted and
  /// what is skipped — belongs to `rust/diting-backup-core`. A group whose local snapshot cannot be
  /// read is reported in [BackupExportResult.skipped] and left out; it never aborts the export.
  Future<BackupExportResult> exportTo(
    BackupChunkSink sink,
    BackupExportSource source, {
    Set<BackupGroup>? groups,
  }) async {
    final selected = groups ?? BackupGroup.values.toSet();
    final fields = await _snapshot(source, selected);
    final now = DateTime.now();
    final answer = RustBackupCore.instance.exportDocument({
      'nowMs': now.millisecondsSinceEpoch,
      'groups': [
        for (final group in BackupGroup.values)
          if (selected.contains(group)) group.key,
      ],
      'fields': fields,
    });

    final content = answer['content'] as String? ?? '';
    for (final chunk in _chunks(content)) {
      await sink(chunk);
    }

    final included = <BackupGroup>[
      for (final key in answer['included'] as List? ?? const [])
        ?BackupGroup.fromKey('$key'),
    ];
    final rawCounts = answer['counts'] as Map? ?? const {};
    final counts = <BackupGroup, int>{
      for (final group in included) group: rawCounts[group.key] as int? ?? 0,
    };
    final skipped = <String>[
      for (final entry in answer['skipped'] as List? ?? const [])
        _skipMessage(entry),
    ];
    for (final message in skipped) {
      source.onSkip?.call(message);
    }

    return BackupExportResult(
      // Streamed: the document went to the sink, so nothing is kept here.
      content: '',
      fileName: '${BackupFormat.fileNamePrefix}-${BackupFormat.stampOf(now)}.json',
      included: included,
      counts: counts,
      skipped: skipped,
    );
  }

  static Iterable<String> _chunks(String content) sync* {
    if (content.length <= _chunkBytes) {
      yield content;
      return;
    }
    var start = 0;
    while (start < content.length) {
      final end = start + _chunkBytes < content.length
          ? start + _chunkBytes
          : content.length;
      yield content.substring(start, end);
      start = end;
    }
  }

  /// `服务商：服务商配置不是合法 JSON`, so the user sees which group is missing and why.
  static String _skipMessage(Object? entry) {
    final key = entry is Map ? entry['group'] : null;
    final reason = entry is Map ? entry['reason'] : null;
    final group = BackupGroup.fromKey(key is String ? key : null);
    final title = group?.title(currentL10n) ?? '$key';
    return '$title：${_reasonMessage('$reason')}';
  }

  static String _reasonMessage(String reason) => switch (reason) {
    'providersInvalidJson' => currentL10n.backupErrProvidersInvalidJson,
    'bootstrapInvalidJson' => currentL10n.backupErrBootstrapInvalidJson,
    _ => reason,
  };
}
