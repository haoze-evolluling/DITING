library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/backup/backup_importer.dart';
import 'package:diting_android/data/backup/backup_models.dart';
import 'package:diting_android/pages/forms/form_page.dart';
import 'package:diting_android/state/backup_providers.dart';
import 'package:diting_android/state/system_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ConfigTransferWebdavPage extends ConsumerStatefulWidget {
  const ConfigTransferWebdavPage({super.key});

  @override
  ConsumerState<ConfigTransferWebdavPage> createState() =>
      _ConfigTransferWebdavPageState();
}

class _ConfigTransferWebdavPageState
    extends ConsumerState<ConfigTransferWebdavPage> {
  /// Upload or download in flight; both buttons are disabled so the file is never written twice.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final dav = ref.watch(davProvider);
    final field = ref.read(davProvider.notifier);
    final canTransfer = dav.status == DavStatus.connected && !_busy;
    return CommonScaffold(
      title: context.l10n.transferWebdav,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.reset,
          tooltip: context.l10n.webdavClearConfig,
          onPressed: dav.status == DavStatus.connecting
              ? null
              : () => ref.read(davProvider.notifier).reset(),
        ),
      ],
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _DavStatusCard(status: dav.status, message: dav.message),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: FormPage(
                title: '',
                padding: EdgeInsets.zero,
                onSave: dav.isConfigured
                    ? () => ref.read(davProvider.notifier).test()
                    : null,
                saving: dav.status == DavStatus.connecting,
                saveLabel: context.l10n.webdavTest,
                children: [
                  FormRowTextField(
                    title: context.l10n.webdavServer,
                    value: dav.server,
                    hintText: 'https://dav.example.com',
                    keyboardType: TextInputType.url,
                    invalid:
                        dav.status == DavStatus.failed && dav.server.isEmpty,
                    onChanged: (value) => field.update(
                      (state) =>
                          state.copyWith(server: value, status: DavStatus.idle),
                    ),
                  ),
                  FormRowTextField(
                    title: context.l10n.webdavUsername,
                    value: dav.username,
                    invalid:
                        dav.status == DavStatus.failed && dav.username.isEmpty,
                    onChanged: (value) => field.update(
                      (state) => state.copyWith(
                        username: value,
                        status: DavStatus.idle,
                      ),
                    ),
                  ),
                  FormRowSecretTextField(
                    title: context.l10n.webdavPassword,
                    controller: _passwordController(),
                    onChanged: (value) => field.update(
                      (state) => state.copyWith(password: value),
                    ),
                  ),
                  FormRowTextField(
                    title: context.l10n.webdavPath,
                    value: dav.path,
                    hintText: '/diting/',
                    monospace: true,
                    onChanged: (value) =>
                        field.update((state) => state.copyWith(path: value)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: TonalButton(
                    label: context.l10n.webdavTest,
                    glyph: AppGlyphs.sync,
                    size: TonalButtonSize.section,
                    onPressed: _busy
                        ? null
                        : () => ref.read(davProvider.notifier).test(),
                  ),
                ),
                Expanded(
                  child: TonalButton(
                    label: context.l10n.commonClearAll,
                    glyph: AppGlyphs.broom,
                    size: TonalButtonSize.section,
                    onPressed: _busy
                        ? null
                        : () => ref.read(davProvider.notifier).reset(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: TonalButton(
                    label: context.l10n.webdavUpload,
                    glyph: AppGlyphs.export,
                    size: TonalButtonSize.section,
                    onPressed: canTransfer ? _upload : null,
                  ),
                ),
                Expanded(
                  child: TonalButton(
                    label: context.l10n.webdavDownload,
                    glyph: AppGlyphs.importFile,
                    size: TonalButtonSize.section,
                    onPressed: canTransfer ? _download : null,
                  ),
                ),
              ],
            ),
          ),
          ListFooter(
            text: context.l10n.webdavFooter(
              canTransfer ? '' : context.l10n.webdavFooterConnected,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// The password controller lives outside the provider: a `TextEditingController` is
  /// mutable, so rebuilding it resets the caret. The provider-scoped wrapper caches it.
  TextEditingController _passwordController() {
    final cached = ref.watch(_passwordControllerProvider);
    final password = ref.read(davProvider).password;
    if (cached.text != password) {
      cached.value = TextEditingValue(
        text: password,
        selection: TextSelection.collapsed(offset: password.length),
      );
    }
    return cached;
  }

  /// Generates the JSON with the backup page's generator, then `PUT`s it. One generator
  /// keeps file export and cloud upload byte-equivalent.
  Future<void> _upload() async {
    setState(() => _busy = true);
    try {
      final actions = ref.read(backupActionsProvider);
      final export = await actions.export(BackupGroup.values.toSet());
      if (!mounted) return;
      if (export.isEmpty) {
        _toast(context.l10n.webdavNoConfig);
        return;
      }
      final result = await ref
          .read(davProvider.notifier)
          .upload(export.content);
      if (!mounted) return;
      _toast(
        result.succeeded
            ? context.l10n.webdavUploadedCount(
                export.included.length,
                export.totalItems,
              )
            : (result.error ?? context.l10n.webdavUploadFailed),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final text = await ref.read(davProvider.notifier).download();
      if (!mounted) return;
      if (text == null) {
        _toast(ref.read(davProvider).message ?? context.l10n.webdavNoCloudBackup);
        return;
      }
      final result = await ref
          .read(backupActionsProvider)
          .importText(text, sourceName: DavNotifier.remoteFileName);
      if (!mounted) return;
      await showFloatingDialog<void>(
        context: context,
        child: _DavImportDialog(result: result),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _DavImportDialog extends StatelessWidget {
  const _DavImportDialog({required this.result});

  final BackupImportResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonDialog(
      title: context.l10n.webdavRestoreTitle,
      trailing: MetaChip(label: result.failed ? context.l10n.webdavRestoreFailed : context.l10n.webdavRestoreDone),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.transferDone),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          if (result.failed)
            Text(result.fatalError!, style: TextStyle(color: colorScheme.error))
          else ...[
            Text(
              context.l10n.webdavRestoreSummary(
                result.added,
                result.updated,
                result.skipped,
              ),
              style: context.listTitleStyle,
            ),
            for (final outcome in result.changed)
              Text(
                context.l10n.webdavOutcomeRow(
                  outcome.group.title(context.l10n),
                  outcome.added,
                  outcome.skipped,
                ),
              ),
            for (final outcome in result.failedGroups)
              Text(
                context.l10n.transferFailedGroupRow(
                  outcome.group.title(context.l10n),
                  outcome.error ?? '',
                ),
                style: TextStyle(color: colorScheme.error),
              ),
            if (result.changed.isEmpty && result.failedGroups.isEmpty)
              Text(context.l10n.webdavNothingChanged),
          ],
        ],
      ),
    );
  }
}

final _passwordControllerProvider = Provider<TextEditingController>((ref) {
  final controller = TextEditingController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Connection badge (upstream `_DavConnectionIndicator`). Each of the three states has its
/// own color and glyph: color alone cannot separate "connecting" from "not connected".
class _DavStatusCard extends StatelessWidget {
  const _DavStatusCard({required this.status, this.message});

  final DavStatus status;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (color, glyph) = switch (status) {
      DavStatus.idle => (colorScheme.onSurfaceVariant, AppGlyphs.cloudSync),
      DavStatus.connecting => (colorScheme.warning, AppGlyphs.sync),
      DavStatus.connected => (colorScheme.success, AppGlyphs.checkCircle),
      DavStatus.failed => (colorScheme.error, AppGlyphs.error),
    };
    return CommonCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      isError: status == DavStatus.failed,
      child: Row(
        spacing: 10,
        children: [
          if (status == DavStatus.connecting)
            CommonCircleLoading(color: color)
          else
            GlyphIcon(glyph, size: 20, color: color),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  status.label(context.l10n),
                  style: context.listTitleStyle.copyWith(color: color),
                ),
                Text(
                  message ?? _hintOf(context.l10n, status),
                  style: context.listCaptionStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _hintOf(AppL10n l10n, DavStatus status) => switch (status) {
    DavStatus.idle => l10n.webdavHintIdle,
    DavStatus.connecting => l10n.webdavHintConnecting,
    DavStatus.connected => l10n.webdavHintConnected,
    DavStatus.failed => l10n.webdavHintFailed,
  };
}
