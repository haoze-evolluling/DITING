/// First level of one log file: file information, an entry card to its full text, and the
/// per-file share/download/delete actions. Pops with a [TroubleshootLogSheetResult] so
/// [TroubleshootingLogsPage] can toast, refresh, or open the text page once the sheet is gone.
library;

import 'package:diting_android/data/native/troubleshooting_log_bridge.dart';
import 'package:diting_android/state/troubleshooting_log_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// What the sheet did before it closed; the timeline turns it into a toast, a refresh or a push.
enum TroubleshootLogSheetAction { content, shared, downloaded, deleted }

/// The sheet's answer. [path] only carries a value for [TroubleshootLogSheetAction.downloaded],
/// where it is the exact `Download/<name>` the file landed at (MediaStore may rename a duplicate).
class TroubleshootLogSheetResult {
  const TroubleshootLogSheetResult._(this.action, this.path);

  const TroubleshootLogSheetResult.content()
    : this._(TroubleshootLogSheetAction.content, null);

  const TroubleshootLogSheetResult.shared()
    : this._(TroubleshootLogSheetAction.shared, null);

  const TroubleshootLogSheetResult.deleted()
    : this._(TroubleshootLogSheetAction.deleted, null);

  const TroubleshootLogSheetResult.downloaded(this.path)
    : action = TroubleshootLogSheetAction.downloaded;

  final TroubleshootLogSheetAction action;
  final String? path;
}

class TroubleshootingLogDetailSheet extends ConsumerStatefulWidget {
  const TroubleshootingLogDetailSheet({super.key, required this.entry});

  final TroubleshootLogEntry entry;

  @override
  ConsumerState<TroubleshootingLogDetailSheet> createState() =>
      _TroubleshootingLogDetailSheetState();
}

class _TroubleshootingLogDetailSheetState
    extends ConsumerState<TroubleshootingLogDetailSheet> {
  bool _busy = false;

  void _openContent() =>
      Navigator.of(context).pop(const TroubleshootLogSheetResult.content());

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final shared = await ref
        .read(troubleshootingLogBridgeProvider)
        .share(widget.entry);
    if (!mounted) return;
    if (!shared) {
      setState(() => _busy = false);
      showAppSnack(context, context.l10n.troubleshootLogsShareFailed);
      return;
    }
    Navigator.of(context).pop(const TroubleshootLogSheetResult.shared());
  }

  /// Writes the file into Download and hands the exact path back to the page for the toast.
  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref
        .read(troubleshootingLogBridgeProvider)
        .download(widget.entry);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _busy = false);
      showAppSnack(context, context.l10n.troubleshootLogsDownloadFailed);
      return;
    }
    Navigator.of(context)
        .pop(TroubleshootLogSheetResult.downloaded(result.path));
  }

  Future<void> _delete() async {
    if (_busy) return;
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.troubleshootLogsDeleteTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.troubleshootLogsDeleteBody(widget.entry.name)),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final deleted = await ref
        .read(troubleshootingLogBridgeProvider)
        .delete(widget.entry);
    if (!mounted) return;
    if (!deleted) {
      setState(() => _busy = false);
      showAppSnack(context, context.l10n.troubleshootLogsDeleteFailed);
      return;
    }
    Navigator.of(context).pop(const TroubleshootLogSheetResult.deleted());
  }

  String _kindLabel() => widget.entry.isRuntime
      ? context.l10n.troubleshootLogKindRuntime
      : context.l10n.troubleshootLogKindCrash;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return CommonScaffold(
      title: widget.entry.name,
      body: PageBody(
        children: [
          SectionBlock(
            title: l10n.troubleshootLogsDetailInfo,
            child: CommonCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              inert: true,
              child: Column(
                children: [
                  KeyValueRow(
                    label: l10n.troubleshootLogsFileName,
                    value: widget.entry.name,
                  ),
                  KeyValueRow(
                    label: l10n.troubleshootLogsFileType,
                    value: _kindLabel(),
                  ),
                  KeyValueRow(
                    label: l10n.troubleshootLogsFileSize,
                    value: widget.entry.sizeLabel,
                    tabular: true,
                  ),
                  KeyValueRow(
                    label: l10n.troubleshootLogsModifiedAt,
                    value: widget.entry.timeLabel,
                    tabular: true,
                  ),
                ],
              ),
            ),
          ),
          SectionBlock(
            title: l10n.troubleshootLogsLogContent,
            child: CommonCard(
              onPressed: _busy ? null : _openContent,
              padding: const EdgeInsets.all(14),
              child: Row(
                spacing: 12,
                children: [
                  const GlyphIcon(AppGlyphs.textShort, size: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          l10n.troubleshootLogsViewContent,
                          style: AppTextRole.rowTitle.of(context),
                        ),
                        Text(
                          l10n.troubleshootLogsViewContentBody,
                          style: AppTextRole.caption
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                ],
              ),
            ),
          ),
          generateSection(
            title: l10n.troubleshootLogsActions,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.send, size: 20),
                title: Text(l10n.troubleshootLogsShare),
                onTap: _busy ? null : _share,
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.cloudDownload, size: 20),
                title: Text(l10n.troubleshootLogsDownload),
                onTap: _busy ? null : _download,
              ),
              ListItem(
                leading: GlyphIcon(
                  AppGlyphs.delete,
                  size: 20,
                  color: colorScheme.error,
                ),
                title: Text(
                  l10n.commonDelete,
                  style: AppTextRole.rowTitle
                      .of(context)
                      .copyWith(color: colorScheme.error),
                ),
                onTap: _busy ? null : _delete,
              ),
            ],
            footer: l10n.troubleshootLogsFooter,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
