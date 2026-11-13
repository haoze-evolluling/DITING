/// First level of one log file: file information, an entry card to its full text, and the
/// per-file share/delete actions. Pops with `'shared'`, `'deleted'`, or `'content'` so
/// [TroubleshootingLogsPage] can toast, refresh, or open the text page once the sheet is gone.
library;

import 'package:diting_android/data/native/troubleshooting_log_bridge.dart';
import 'package:diting_android/state/troubleshooting_log_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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

  void _openContent() => Navigator.of(context).pop('content');

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final shared = await ref
        .read(troubleshootingLogBridgeProvider)
        .share(widget.entry);
    if (!mounted) return;
    if (!shared) {
      setState(() => _busy = false);
      _toast(context.l10n.troubleshootLogsShareFailed);
      return;
    }
    Navigator.of(context).pop('shared');
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
      _toast(context.l10n.troubleshootLogsDeleteFailed);
      return;
    }
    Navigator.of(context).pop('deleted');
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
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
                          style: context.listTitleStyle,
                        ),
                        Text(
                          l10n.troubleshootLogsViewContentBody,
                          style: AppTextStyle.caption1
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
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.send, size: 20),
                title: Text(l10n.troubleshootLogsShare),
                onTap: _busy ? null : _share,
              ),
              ListItem(
                leading: GlyphIcon(
                  AppGlyphs.delete,
                  size: 20,
                  color: colorScheme.error,
                ),
                title: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: colorScheme.error),
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
