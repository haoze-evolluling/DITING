/// Developer options hub, which has no 1.4.3 counterpart. Every action here talks to the real
/// database, native channels or the cleanup service; nothing is simulated.
library;

import 'dart:io';
import 'dart:math';

import 'package:diting_android/data/cleanup/data_cleanup_service.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/db/app_database.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/system_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/glyph_lookup.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Rows in the stress action; one batch, so the UI never freezes mid-way.
const _stressRowCount = 1000;

/// The four actions that do real work. `title` doubles as the running indicator.
enum _DeveloperAction {
  stressLogs(glyphName: 'logs'),
  reportError(glyphName: 'error'),
  clearAllData(glyphName: 'clearAll', destructive: true),
  vacuum(glyphName: 'memory');

  const _DeveloperAction({required this.glyphName, this.destructive = false});

  final String glyphName;
  final bool destructive;

  String title(AppL10n l10n) => switch (this) {
    stressLogs => l10n.devStressLogs,
    reportError => l10n.devErrorReport,
    clearAllData => l10n.devClearAll,
    vacuum => l10n.devVacuum,
  };

  String subtitle(AppL10n l10n) => switch (this) {
    stressLogs => l10n.devStressLogsBody(_stressRowCount),
    reportError => l10n.devErrorReportBody,
    clearAllData => l10n.devClearAllBody,
    vacuum => l10n.devVacuumBody,
  };
}

class DeveloperPage extends ConsumerStatefulWidget {
  const DeveloperPage({super.key});

  @override
  ConsumerState<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends ConsumerState<DeveloperPage> {
  /// Non-null while an action runs; disables the whole list instead of only one row.
  _DeveloperAction? _running;

  /// Bumped after every action. The storage card re-stats the files, and a `const` child would be
  /// skipped by the element tree's identical-widget fast path, leaving the old sizes on screen.
  int _storageRevision = 0;

  Future<void> _handle(_DeveloperAction action) async {
    if (_running != null) return;
    // Captured before the dialogs: the l10n lookup is still valid after `await`, while the
    // analyzer cannot tell that `context` stays mounted across the async gaps.
    final l10n = context.l10n;
    if (action.destructive) {
      final confirmed = await showFloatingDialog<bool>(
        context: context,
        child: CommonDialog(
          title: action.title(l10n),
          destructive: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.devCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.devRun),
            ),
          ],
          child: Text(l10n.devConfirmBody(action.subtitle(l10n))),
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _running = action);
    String message;
    try {
      message = switch (action) {
        _DeveloperAction.stressLogs => await _stressLogs(),
        _DeveloperAction.reportError => _reportError(),
        _DeveloperAction.clearAllData => await _clearAllData(),
        _DeveloperAction.vacuum => await _vacuum(),
      };
    } catch (error) {
      message = l10n.devActionFailed(action.title(l10n), '$error');
    } finally {
      if (mounted) {
        setState(() {
          _running = null;
          _storageRevision++;
        });
      }
    }
    if (!mounted) return;
    showAppSnack(context, message);
    // "Clear all data" also wipes the first-run agreement, so the app must restart; staying alive
    // would leave "running" split from "must agree again" (same rule as the cleanup page).
    if (action == _DeveloperAction.clearAllData) {
      await _offerRestart();
    }
  }

  /// Writes real rows into the active `dns_log`; the revision bump makes the log pages re-query.
  Future<String> _stressLogs() async {
    final l10n = context.l10n;
    final fileName = ref.read(activeLogDatabaseFileProvider);
    final db = await AppDatabase.open(fileName);
    if (db == null) return l10n.devStressNoDb;
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = Random();
    final batch = db.batch();
    for (var index = 0; index < _stressRowCount; index++) {
      batch.insert('dns_log', {
        'timestamp': now - index * 1000,
        'queryName': 'stress-${index.toString().padLeft(4, '0')}.example.com',
        'queryType': 1,
        'result': index.isEven ? 'PASSED' : 'BLOCKED',
        'message': 'developer stress test',
        'cached': random.nextBool() ? 1 : 0,
        'packageName': 'com.haoze.diting',
      });
    }
    final inserted = (await batch.commit(noResult: true)).length;
    ref.read(dnsLogRevisionProvider.notifier).bump();
    return l10n.devStressDone('$inserted', fileName);
  }

  /// Goes through the same handler the framework uses, so it exercises a real error path without
  /// tearing the app down.
  String _reportError() {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(context.l10n.devTestException),
        library: 'diting.developer',
        context: ErrorDescription(context.l10n.devErrorReport),
      ),
    );
    return context.l10n.devErrorReported;
  }

  Future<String> _clearAllData() async {
    final result = await ref
        .read(cleanupRunnerProvider)
        .run(CleanupAction.allData);
    return result.message;
  }

  /// `VACUUM` on every existing database file; the difference in file size is the real gain.
  Future<String> _vacuum() async {
    final l10n = context.l10n;
    var freed = 0;
    final touched = <String>[];
    for (final fileName in StorageContract.allDatabases) {
      final db = await AppDatabase.open(fileName, create: false);
      if (db == null) continue;
      try {
        final file = File(db.path);
        final before = await file.length();
        await db.execute('VACUUM');
        freed += before - await file.length();
        touched.add(fileName);
      } finally {
        await db.close();
      }
    }
    if (touched.isEmpty) return l10n.devVacuumNoDb;
    final kb = (freed / 1024).round();
    return l10n.devVacuumDone(touched.join('、'), kb < 0 ? 0 : kb);
  }

  Future<void> _offerRestart() async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.devRestartNeeded,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.devLater),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.devQuitNow),
          ),
        ],
        child: Text(context.l10n.devClearAllDone),
      ),
    );
    if (confirmed == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(developerModeProvider);
    return CommonScaffold(
      title: context.l10n.devOptions,
      // Avoids `PageBody` (a lazy ListView): this is a directory, and never-built entries stay
      // invisible to the a11y tree and screenshot review. Building them all is cheap.
      body: AppBarClearance(
        // The rows are built eagerly; a boundary under the scroll view lets scrolling move one
        // layer instead of re-recording every row each frame.
        child: SingleChildScrollView(
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _DeveloperModeCard(),
                _StorageCard(revision: _storageRevision),
                generateSection(
                  title: context.l10n.devExperimental,
                  items: [
                    for (final action in _DeveloperAction.values)
                      _ActionRow(
                        action: action,
                        enabled: enabled && _running == null,
                        running: _running == action,
                        onTap: enabled && _running == null
                            ? () => _handle(action)
                            : null,
                      ),
                  ],
                  footer: context.l10n.devFooterWarning(_stressRowCount),
                ),
                ListFooter(text: context.l10n.devFooterMoved),
                const DockSpacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// When off the actions are disabled, not hidden, so the user sees where to enable them.
class _DeveloperModeCard extends ConsumerWidget {
  const _DeveloperModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(developerModeProvider);
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Row(
              spacing: 10,
              children: [
                GlyphIcon(
                  AppGlyphs.wrench,
                  size: 22,
                  color: enabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.devWarningTitle,
                        style: context.listTitleStyle,
                      ),
                      Text(
                        enabled
                            ? context.l10n.devUnlocked
                            : context.l10n.devLocked,
                        style: context.listCaptionStyle,
                      ),
                    ],
                  ),
                ),
                CommonSwitch(
                  value: enabled,
                  onChanged: (value) =>
                      ref.read(developerModeProvider.notifier).toggle(value),
                ),
              ],
            ),
            InlineNotice(message: context.l10n.devWarning),
          ],
        ),
      ),
    );
  }
}

/// Read-only summary of the V2 stores.
class _StorageCard extends ConsumerWidget {
  const _StorageCard({required this.revision});

  /// Changes after every action so the size probe runs again.
  final int revision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final state = settings.storageV2State;
    final error = settings.storageV2Error;
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Row(
              spacing: 10,
              children: [
                GlyphIcon(
                  AppGlyphs.database,
                  size: 22,
                  color: colorScheme.primary,
                ),
                Expanded(
                  child: Text(
                    context.l10n.devStorageTitle,
                    style: context.listTitleStyle,
                  ),
                ),
              ],
            ),
            Text(
              state >= StorageContract.stateVerified
                  ? context.l10n.devStorageV2Ready
                  : context.l10n.devStorageV2Pending,
              style: context.listCaptionStyle,
            ),
            Text(
              context.l10n.devStorageV2Detail(
                '$state',
                _formatDate(settings.storageV2CompletedAt),
              ),
              style: context.listCaptionStyle,
            ),
            if (error != null && state < StorageContract.stateVerified)
              Text(
                context.l10n.devStorageV2Error(error),
                style: context.listCaptionStyle.copyWith(
                  color: colorScheme.error,
                ),
              ),
            FutureBuilder<int>(
              key: ValueKey(revision),
              future: _databaseBytes(),
              builder: (context, snapshot) {
                final bytes = snapshot.data ?? 0;
                if (bytes <= 0) return const SizedBox.shrink();
                return Text(
                  context.l10n.devStorageV2Files((bytes / 1024).round()),
                  style: context.listCaptionStyle,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static Future<int> _databaseBytes() async {
    final directory = await getDatabasesPath();
    var total = 0;
    for (final name in StorageContract.allDatabases) {
      for (final suffix in const ['', '-wal', '-shm']) {
        final file = File(p.join(directory, '$name$suffix'));
        if (await file.exists()) total += await file.length();
      }
    }
    return total;
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.enabled,
    required this.running,
    required this.onTap,
  });

  final _DeveloperAction action;
  final bool enabled;
  final bool running;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final Color glyphColor;
    if (!enabled) {
      glyphColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
    } else if (action.destructive) {
      glyphColor = colorScheme.error;
    } else {
      glyphColor = colorScheme.onSurfaceVariant;
    }
    return ListItem(
      title: Text(
        action.title(context.l10n),
        style: action.destructive && enabled
            ? context.listTitleStyle.copyWith(color: colorScheme.error)
            : null,
      ),
      subtitle: Text(
        running ? context.l10n.devRunning : action.subtitle(context.l10n),
      ),
      leading: running
          ? const CommonCircleLoading(size: 20)
          : GlyphIcon(glyphByName(action.glyphName), color: glyphColor),
      trailing: running
          ? null
          : const GlyphIcon(AppGlyphs.chevronForward, size: 20),
      onTap: onTap,
    );
  }
}
