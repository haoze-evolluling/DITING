/// First-launch gate for the one-time V2 storage migration.
///
/// The gate runs before the app's provider tree exists, so it only touches prefs, sqflite and the
/// native storage channel. It replaces itself with the real app by calling [onReady].
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/data_plane_status.dart';
import 'package:diting_shared/data/db/storage_v2_migration.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/ui/typography.dart';
import 'package:material_ui/material_ui.dart';

class StorageV2GateApp extends StatefulWidget {
  const StorageV2GateApp({
    super.key,
    required this.store,
    required this.onReady,
    this.native = const MethodChannelStorageV2Native(),
  });

  final LegacyPrefsStore store;

  /// Starts the real application. Called once, after the stores verify.
  final Future<void> Function() onReady;

  final StorageV2Native native;

  @override
  State<StorageV2GateApp> createState() => _StorageV2GateAppState();
}

class _StorageV2GateAppState extends State<StorageV2GateApp> {
  StorageV2Progress? _progress;
  String? _error;
  bool _needsStop = false;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (!mounted) return;
    setState(() {
      _running = true;
      _error = null;
      _needsStop = false;
    });
    final dataPlaneRunning = await anyDataPlaneRunning();
    if (!mounted) return;
    if (dataPlaneRunning) {
      setState(() {
        _running = false;
        _needsStop = true;
      });
      return;
    }
    final result = await ensureStorageV2(
      widget.store,
      dataPlaneRunning: false,
      native: widget.native,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      },
    );
    await _finish(result, deferred: result.deferred);
  }

  Future<void> _finish(StorageV2Result result, {required bool deferred}) async {
    if (!mounted) return;
    if (result.ready) {
      await widget.onReady();
      return;
    }
    setState(() {
      _running = false;
      _error = result.error;
      _needsStop = deferred;
    });
  }

  Future<void> _stopAndRetry() async {
    setState(() => _running = true);
    final stopped = await stopAllDataPlanes();
    if (!mounted) return;
    if (!stopped) {
      setState(() {
        _running = false;
        _needsStop = true;
        _error = null;
      });
      return;
    }
    await _run();
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.storageV2DiscardTitle),
        content: Text(context.l10n.storageV2DiscardConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.devCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.storageV2Discard),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _running = true;
      _error = null;
    });
    final result = await discardStorageV2(widget.store, native: widget.native);
    await _finish(result, deferred: false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F7CFF),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4F7CFF),
      ),
      localizationsDelegates: [
        AppL10n.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: _GateBody(
        progress: _progress,
        error: _error,
        needsStop: _needsStop,
        running: _running,
        onStopAndRetry: _stopAndRetry,
        onRetry: _run,
        onDiscard: _discard,
      ),
    );
  }
}

class _GateBody extends StatelessWidget {
  const _GateBody({
    required this.progress,
    required this.error,
    required this.needsStop,
    required this.running,
    required this.onStopAndRetry,
    required this.onRetry,
    required this.onDiscard,
  });

  final StorageV2Progress? progress;
  final String? error;
  final bool needsStop;
  final bool running;
  final VoidCallback onStopAndRetry;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final progress = this.progress;
    final String message;
    if (progress?.phase == 'copy' && progress?.database != null) {
      message = l10n.storageV2Progress(
        progress!.database!,
        progress.current + 1,
        progress.total,
      );
    } else if (progress?.phase == 'native' || progress?.phase == 'verify') {
      message = l10n.storageV2Verifying;
    } else {
      message = l10n.storageV2Preparing;
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 18,
                children: [
                  Text(
                    l10n.storageV2Title,
                    textAlign: TextAlign.center,
                    style: AppTextRole.cardTitle.of(context),
                  ),
                  if (running) const Center(child: CircularProgressIndicator()),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTextRole.body.of(context),
                  ),
                  if (needsStop) ...[
                    Text(
                      l10n.storageV2NeedStop,
                      textAlign: TextAlign.center,
                      style: AppTextRole.body
                          .of(context)
                          .copyWith(color: theme.colorScheme.error),
                    ),
                    FilledButton(
                      onPressed: onStopAndRetry,
                      child: Text(l10n.storageV2StopAndRetry),
                    ),
                  ],
                  if (error != null && !needsStop) ...[
                    Text(
                      l10n.storageV2Failed(error!),
                      textAlign: TextAlign.center,
                      style: AppTextRole.body
                          .of(context)
                          .copyWith(color: theme.colorScheme.error),
                    ),
                    FilledButton(
                      onPressed: running ? null : onRetry,
                      child: Text(l10n.storageV2Retry),
                    ),
                    TextButton(
                      onPressed: running ? null : onDiscard,
                      child: Text(l10n.storageV2Discard),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
