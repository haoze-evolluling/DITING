part of 'subscriptions_page.dart';

/// Built from `CommonCard` + `ListItem` so the design system owns radius, pressed state and
/// fills. `SubscriptionImportState` drives three looks: `ready`, `importing` and `failed`.
class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.entry,
    required this.isUpdating,
    required this.busy,
    required this.onToggle,
    required this.onUpdate,
    required this.onDelete,
    required this.onEdit,
    required this.onConfigure,
  });

  final SubscriptionEntry entry;

  final bool isUpdating;

  /// Any update is running, so every update entry point is disabled to avoid concurrent
  /// writes to the same data.
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  /// Opens the full edit sheet (address, kind, group, mirror).
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final hasError = entry.isFailed;
    final mirror = entry.record.mirrorTemplate;
    return CommonCard(
      isError: hasError,
      // A disabled subscription dims the whole card: showing it only on the switch makes
      // "rules not applied" look like a bug.
      child: Opacity(
        opacity: entry.enabled ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListItem(
              leading: GlyphIcon(
                entry.isRemote ? AppGlyphs.cloudSync : AppGlyphs.importFile,
                size: 20,
                color: hasError ? colorScheme.error : colorScheme.primary,
              ),
              title: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.listTitleStyle,
              ),
              subtitle: Text(
                '${entry.groupKey} · ${entry.kind.displayName(context.l10n)}'
                ' · ${entry.sourceType.label(context.l10n)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.listSubtitleStyle,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  CommonSwitch(value: entry.enabled, onChanged: onToggle),
                  CommonPopupBox(
                    targetBuilder: (open) => IconButton(
                      tooltip: UiLocalizations.of(context).more,
                      onPressed: open,
                      icon: const GlyphIcon(AppGlyphs.more),
                    ),
                    popupBuilder: (_) => CommonPopupMenu(
                      items: [
                        CommonPopupMenuItem(
                          // Local rows re-read the picked file instead of downloading it.
                          label: entry.isRemote
                              ? context.l10n.subsUpdateNow
                              : context.l10n.subsReimport,
                          glyph: AppGlyphs.refresh,
                          onPressed: busy ? null : onUpdate,
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.subsEdit,
                          glyph: AppGlyphs.sliders,
                          // Saving may re-download, which must not overlap a running update.
                          onPressed: busy ? null : onConfigure,
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.subsRename,
                          glyph: AppGlyphs.edit,
                          onPressed: onEdit,
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.subsDeleteTitle,
                          glyph: AppGlyphs.delete,
                          danger: true,
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      MetaChip(label: _lineCountLabel(entry, context.l10n)),
                      MetaChip(label: _updatedLabel(entry, context.l10n)),
                      if (entry.consecutiveFailureCount > 0)
                        MetaChip(
                          label: context.l10n.subsConsecutiveFailures(
                            entry.consecutiveFailureCount,
                          ),
                        ),
                      if (!entry.isRemote) MetaChip(label: context.l10n.subsLocalFileSubscription),
                      if (mirror != null)
                        MetaChip(
                          label: entry.record.mirrorFallback
                              ? context.l10n.subsMirrorFallbackShort
                              : context.l10n.subsMirrorNoFallback,
                        ),
                    ],
                  ),
                  Text(
                    // A local row stores its SAF address, which is far too long to show; the
                    // file name (last path segment) is what the user recognises.
                    entry.isRemote ? entry.url : _fileNameOf(entry.url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.listCaptionStyle.copyWith(
                      fontFamily: appMonospaceFontFamily,
                    ),
                  ),
                  if (mirror != null)
                    Text(
                      context.l10n.subsMirrorName(mirror),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.listCaptionStyle.copyWith(
                        fontFamily: appMonospaceFontFamily,
                      ),
                    ),
                  if (hasError)
                    Row(
                      spacing: 6,
                      children: [
                        GlyphIcon(
                          AppGlyphs.error,
                          size: 16,
                          color: colorScheme.error,
                        ),
                        Expanded(
                          child: Text(
                            entry.importError ?? context.l10n.subsLastUpdateFailed,
                            style: context.listCaptionStyle.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (entry.isImporting || isUpdating)
                    LinearProgressIndicator(
                      minHeight: 3,
                      borderRadius: AppRadius.full,
                    ),
                  Text(
                    context.l10n.subsRulesStored(
                      _formatCount(entry.ruleCount),
                      entry.isRemote
                          ? context.l10n.subsActionRemote
                          : context.l10n.subsActionLocal,
                    ),
                    style: context.listCaptionStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Last segment of a `content://` address, which is the file name the picker reported.
  static String _fileNameOf(String uri) {
    final segment = Uri.tryParse(uri)?.pathSegments.lastOrNull ?? uri;
    return segment.isEmpty ? uri : segment;
  }

  static String _lineCountLabel(SubscriptionEntry entry, AppL10n l10n) =>
      l10n.subsRuleCountValue(_formatCount(entry.ruleCount));

  static String _updatedLabel(SubscriptionEntry entry, AppL10n l10n) {
    if (entry.lastUpdated <= 0) {
      return l10n.subsNeverUpdated;
    }
    return _formatTimestamp(entry.lastUpdated);
  }
}

/// Epoch milliseconds to `MM-dd HH:mm`. Minutes are enough because updates happen on an
/// hourly scale, and seconds would make two updates in the same minute look identical.
String _formatTimestamp(int epochMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
