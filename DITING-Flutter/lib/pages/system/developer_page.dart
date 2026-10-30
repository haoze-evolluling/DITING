/// Developer options hub, which has no 1.4.3 counterpart. Every action here talks to the real
/// database, native channels or the cleanup service; nothing is simulated.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'dart:io';
import 'dart:math';

import 'package:diting/data/cleanup/data_cleanup_service.dart';
import 'package:diting/data/db/legacy_database.dart';
import 'package:diting/routes/config_routes.dart';
import 'package:diting/routes/hub_routes.dart';
import 'package:diting/routes/observability_routes.dart';
import 'package:diting/routes/system_routes.dart';
import 'package:diting/state/cleanup_providers.dart';
import 'package:diting/state/log_providers.dart';
import 'package:diting/state/system_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/glyph_lookup.dart';
import 'package:diting/widgets/nav_entry_row.dart';
import 'package:diting/widgets/notice.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
      };
    } catch (error) {
      message = context.l10n.devActionFailed(action.title(context.l10n), '$error');
    } finally {
      if (mounted) setState(() => _running = null);
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
    for (final fileName in const [
      LegacyDatabase.mainFile,
      LegacyDatabase.expressFile,
      LegacyDatabase.serverFile,
    ]) {
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
              generateSection(
                title: context.l10n.devDiagnostics,
                items: [
                  NavEntryRow(
                    glyph: AppGlyphs.target,
                    leadingSize: 20,
                    title: context.l10n.devIpQuality,
                    subtitle: context.l10n.devIpQualityBody,
                    onPressed: () => context.push(SystemPaths.ipQuality),
                  ),
                  NavEntryRow(
                    glyph: AppGlyphs.requests,
                    leadingSize: 20,
                    title: context.l10n.devRequestLogs,
                    subtitle: context.l10n.devRequestLogsBody,
                    onPressed: () => context.push(ObservabilityPaths.requests),
                  ),
                  NavEntryRow(
                    glyph: AppGlyphs.logs,
                    leadingSize: 20,
                    title: context.l10n.devLogRetention,
                    subtitle: context.l10n.devLogRetentionBody,
                    onPressed: () => context.push(HubPaths.logRetention),
                  ),
                  NavEntryRow(
                    glyph: AppGlyphs.wrench,
                    leadingSize: 20,
                    title: context.l10n.devTroubleshoot,
                    subtitle: context.l10n.devTroubleshootBody,
                    onPressed: () => context.push(HubPaths.troubleshooting),
                  ),
                  NavEntryRow(
                    glyph: AppGlyphs.broom,
                    leadingSize: 20,
                    title: context.l10n.devDataCleanup,
                    subtitle: context.l10n.devDataCleanupBody,
                    onPressed: () => context.push(HubPaths.dataCleanup),
                  ),
                ],
              ),
              generateSection(
                title: context.l10n.devConfigSection,
                items: [
                  NavEntryRow(
                    glyph: AppGlyphs.resources,
                    leadingSize: 20,
                    title: context.l10n.devCustomResources,
                    subtitle: context.l10n.devCustomResourcesBody,
                    onPressed: () => context.push(ConfigPaths.customResources),
                  ),
                  NavEntryRow(
                    glyph: AppGlyphs.account,
                    leadingSize: 20,
                    title: 'User-Agent',
                    subtitle: context.l10n.devUserAgentBody,
                    onPressed: () => context.push(ConfigPaths.userAgents),
                  ),
                  NavEntryRow(
                    glyph: AppGlyphs.wifi,
                    leadingSize: 20,
                    title: context.l10n.devOnDemand,
                    subtitle: context.l10n.devOnDemandBody,
                    onPressed: () => context.push(ConfigPaths.onDemand),
                  ),
                  NavEntryRow(
                    glyph: AppGlyphs.cloudSync,
                    leadingSize: 20,
                    title: context.l10n.devWebdav,
                    subtitle: context.l10n.devWebdavBody,
                    onPressed: () =>
                        context.push(HubPaths.configTransferWebdav),
                  ),
                ],
              ),
              generateSection(
                title: context.l10n.devUiSection,
                items: [
                  NavEntryRow(
                    glyph: AppGlyphs.font,
                    leadingSize: 20,
                    title: context.l10n.devFontFamily,
                    subtitle: context.l10n.devFontFamilyBody,
                    onPressed: () => context.push(SystemPaths.fontFamily),
                  ),
                  NavEntryRow(
                    glyph: AppGlyphs.textSize,
                    leadingSize: 20,
                    title: context.l10n.devFontSize,
                    subtitle: context.l10n.devFontSizeBody,
                    onPressed: () => context.push(SystemPaths.theme),
                  ),
                  NavEntryRow(
                    glyph: AppGlyphs.motion,
                    leadingSize: 20,
                    title: context.l10n.devTabAnimation,
                    subtitle: context.l10n.devTabAnimationBody,
                    onPressed: () => context.push(SystemPaths.theme),
                  ),
                ],
              ),
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
                    context.l10n.devFooterLegacy,
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
            ? TextStyle(color: colorScheme.error)
            : null,
      ),
      subtitle: Text(
        running ? context.l10n.devRunning : action.subtitle(context.l10n),
      ),
      leading: running
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
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
