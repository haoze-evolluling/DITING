/// Developer options hub, which has no 1.4.3 counterpart. Every action here talks to the real
/// database, native channels or the cleanup service; nothing is simulated.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:io';
import 'dart:math';

import 'package:diting_android/data/cleanup/data_cleanup_service.dart';
import 'package:diting_android/data/native/data_plane_status.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/db/storage_migration.dart';
import 'package:diting_shared/data/db/storage_reclaim.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/system_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/glyph_lookup.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Rows in the stress action; one batch, so the UI never freezes mid-way.
const _stressRowCount = 1000;

/// The four actions that do real work. `title` doubles as the running indicator.
enum _DeveloperAction {
  stressLogs(glyphName: 'logs'),
  reportError(glyphName: 'error'),
  clearAllData(glyphName: 'clearAll', destructive: true),
  vacuum(glyphName: 'memory'),
  retryMigration(glyphName: 'refresh'),
  reclaimLegacy(glyphName: 'delete', destructive: true);

  const _DeveloperAction({required this.glyphName, this.destructive = false});

  final String glyphName;
  final bool destructive;

  String title(AppL10n l10n) => switch (this) {
    stressLogs => l10n.devStressLogs,
    reportError => l10n.devErrorReport,
    clearAllData => l10n.devClearAll,
    vacuum => l10n.devVacuum,
    retryMigration => l10n.devRetryMigration,
    reclaimLegacy => l10n.devReclaimLegacy,
  };

  String subtitle(AppL10n l10n) => switch (this) {
    stressLogs => l10n.devStressLogsBody(_stressRowCount),
    reportError => l10n.devErrorReportBody,
    clearAllData => l10n.devClearAllBody,
    vacuum => l10n.devVacuumBody,
    retryMigration => l10n.devRetryMigrationBody,
    reclaimLegacy => l10n.devReclaimLegacyBody,
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
    if (action.destructive) {
      final confirmed = await showFloatingDialog<bool>(
        context: context,
        child: CommonDialog(
          title: action.title(context.l10n),
          destructive: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.devCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.devRun),
            ),
          ],
          child: Text(context.l10n.devConfirmBody(action.subtitle(context.l10n))),
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
        _DeveloperAction.retryMigration => await _retryMigration(),
        _DeveloperAction.reclaimLegacy => await _reclaimLegacy(),
      };
    } catch (error) {
      message = context.l10n.devActionFailed(action.title(context.l10n), '$error');
    } finally {
      if (mounted) {
        setState(() {
          _running = null;
          _storageRevision++;
        });
      }
    }
    if (!mounted) return;
    _toast(message);
    // "Clear all data" also wipes the first-run agreement, so the app must restart; staying alive
    // would leave "running" split from "must agree again" (same rule as the cleanup page).
    if (action == _DeveloperAction.clearAllData && mounted) {
      await _offerRestart();
    }
  }

  /// Writes real rows into the active `dns_log`; the revision bump makes the log pages re-query.
  Future<String> _stressLogs() async {
    final fileName = ref.read(activeLogDatabaseFileProvider);
    final db = await LegacyDatabase.open(fileName);
    if (db == null) return context.l10n.devStressNoDb;
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
    return context.l10n.devStressDone('$inserted', fileName);
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
    var freed = 0;
    final touched = <String>[];
    for (final fileName in StorageContract.allKnownDatabases) {
      final db = await LegacyDatabase.open(fileName, create: false);
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
    if (touched.isEmpty) return context.l10n.devVacuumNoDb;
    final kb = (freed / 1024).round();
    return context.l10n.devVacuumDone(touched.join('、'), kb < 0 ? 0 : kb);
  }

  /// Re-runs the startup migration on demand. A running data plane defers it, as on launch.
  Future<String> _retryMigration() async {
    // Captured before the awaits: the message is formatted after the work, and a disposed page
    // must not dereference its context.
    final l10n = context.l10n;
    final result = await ensureSplitStorage(
      ref.read(legacyPrefsStoreProvider),
      dataPlaneRunning: await anyDataPlaneRunning(),
    );
    // Every reader resolving database names watches this revision; bump it even on failure so the
    // card shows the reason that was just recorded.
    ref.read(legacySettingsRevisionProvider.notifier).bump();
    if (result.split) return l10n.devMigrationDone;
    if (result.deferred) return l10n.devMigrationDeferred;
    return l10n.devActionFailed(l10n.devRetryMigration, result.error ?? '');
  }

  /// Deletes the stale pre-split copies. Never touches the server rules file: it kept its legacy
  /// name and is still the live store for DNS mode (see [StorageContract.reclaimableLegacyDatabases]).
  Future<String> _reclaimLegacy() async {
    final l10n = context.l10n;
    if (!ref.read(storageLayoutProvider).isSplit) {
      return l10n.devReclaimNone;
    }
    final sizes = await legacyDatabaseSizes();
    if (sizes.isEmpty) return l10n.devReclaimNone;
    if (await anyDataPlaneRunning()) {
      return l10n.devMigrationDeferred;
    }
    final freed = await reclaimLegacyDatabases(
      split: true,
      dataPlaneRunning: false,
    );
    if (freed <= 0) return l10n.devReclaimNone;
    return l10n.devReclaimDone(
      sizes.keys.join('、'),
      (freed / 1024).round(),
    );
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

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
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
        child: _ScrollLayer(
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
                footer:
                    context.l10n.devFooterWarning(_stressRowCount),
              ),
              ListFooter(
                text:
                    context.l10n.devFooterMoved,
              ),
              const DockSpacer(),
            ],
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
                        enabled ? context.l10n.devUnlocked : context.l10n.devLocked,
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
            InlineNotice(
              message:
                  context.l10n.devWarning,
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only summary of the storage layout, followed by the retry/reclaim actions in the list.
class _StorageCard extends ConsumerWidget {
  const _StorageCard({required this.revision});

  /// Changes after every action so the size probe runs again.
  final int revision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(storageLayoutProvider);
    final settings = ref.watch(legacySettingsProvider);
    final error = settings.storageMigrationError;
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
                  AppGlyphs.layers,
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
              layout.isSplit
                  ? context.l10n.devStorageSplit
                  : context.l10n.devStorageLegacy,
              style: context.listCaptionStyle,
            ),
            Text(
              context.l10n.devStorageDetail(
                settings.storageLayoutVersion,
                _formatDate(settings.storageSplitCompletedAt),
              ),
              style: context.listCaptionStyle,
            ),
            if (error != null && !layout.isSplit)
              Text(
                context.l10n.devStoragePending(error),
                style: context.listCaptionStyle.copyWith(
                  color: colorScheme.error,
                ),
              ),
            FutureBuilder<Map<String, int>>(
              key: ValueKey(revision),
              future: legacyDatabaseSizes(),
              builder: (context, snapshot) {
                final bytes =
                    snapshot.data?.values.fold<int>(0, (sum, size) => sum + size) ??
                    0;
                if (bytes <= 0) return const SizedBox.shrink();
                return Text(
                  context.l10n.devStorageFiles((bytes / 1024).round()),
                  style: context.listCaptionStyle,
                );
              },
            ),
          ],
        ),
      ),
    );
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
    final glyphColor = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
        : action.destructive
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
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

/// [SingleChildScrollView] with its content on its own layer.
class _ScrollLayer extends StatelessWidget {
  const _ScrollLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SingleChildScrollView(child: RepaintBoundary(child: child));
}
