part of 'subscriptions_page.dart';

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

  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final hasError = entry.isFailed;
    final mirror = entry.record.mirrorTemplate;
    return CommonCard(
      isError: hasError,
      child: Opacity(
        opacity: entry.enabled ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListItem(
              leading: Icon(
                entry.isRemote ? TablerIcons.cloud_network : TablerIcons.file_import,
                size: 20,
                color: hasError ? colorScheme.error : colorScheme.primary,
              ),
              title: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.rowTitle.of(context),
              ),
              subtitle: Text(
                '${entry.groupKey} · ${entry.kind.displayName(context.l10n)}'
                ' · ${entry.sourceType.label(context.l10n)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.supportingText.of(context),
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
                      icon: const Icon(TablerIcons.dots),
                    ),
                    popupBuilder: (_) => CommonPopupMenu(
                      items: [
                        CommonPopupMenuItem(
                          label: entry.isRemote
                              ? context.l10n.subsUpdateNow
                              : context.l10n.subsReimport,
                          glyph: TablerIcons.refresh,
                          onPressed: busy ? null : onUpdate,
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.subsEdit,
                          glyph: TablerIcons.adjustments,
                          onPressed: busy ? null : onConfigure,
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.subsRename,
                          glyph: TablerIcons.pencil,
                          onPressed: onEdit,
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.subsDeleteTitle,
                          glyph: TablerIcons.trash,
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
                      if (entry.health != SubscriptionHealth.ok)
                        MetaChip(
                          label: _healthLabel(context.l10n, entry.health),
                        ),
                      if (entry.consecutiveFailureCount > 0)
                        MetaChip(
                          label: context.l10n.subsConsecutiveFailures(
                            entry.consecutiveFailureCount,
                          ),
                        ),
                      if (!entry.isRemote)
                        MetaChip(label: context.l10n.subsLocalFileSubscription),
                      if (mirror != null)
                        MetaChip(
                          label: entry.record.mirrorFallback
                              ? context.l10n.subsMirrorFallbackShort
                              : context.l10n.subsMirrorNoFallback,
                        ),
                    ],
                  ),
                  Text(
                    entry.isRemote ? entry.url : _fileNameOf(entry.url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextRole.supportingText
                        .of(context)
                        .copyWith(fontFeatures: appTabularFigures),
                  ),
                  if (mirror != null)
                    Text(
                      context.l10n.subsMirrorName(mirror),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextRole.supportingText
                          .of(context)
                          .copyWith(fontFeatures: appTabularFigures),
                    ),
                  if (hasError)
                    Row(
                      spacing: 6,
                      children: [
                        Icon(
                          TablerIcons.alert_circle,
                          size: 16,
                          color: colorScheme.error,
                        ),
                        Expanded(
                          child: Text(
                            entry.importError ??
                                context.l10n.subsLastUpdateFailed,
                            style: AppTextRole.supportingText
                                .of(context)
                                .copyWith(color: colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  if (entry.isImporting || isUpdating)
                    LinearProgressIndicator(
                      minHeight: 3,
                      borderRadius: AppRadius.standard,
                    ),
                  Text(
                    context.l10n.subsRulesStored(
                      _formatCount(entry.ruleCount),
                      entry.isRemote
                          ? context.l10n.subsActionRemote
                          : context.l10n.subsActionLocal,
                    ),
                    style: AppTextRole.supportingText.of(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  static String _healthLabel(AppL10n l10n, SubscriptionHealth health) =>
      switch (health) {
        SubscriptionHealth.ok => l10n.subscriptionHealthOk,
        SubscriptionHealth.unchanged => l10n.subscriptionHealthUnchanged,
        SubscriptionHealth.cached => l10n.subscriptionHealthCached,
        SubscriptionHealth.failed => l10n.subscriptionHealthFailed,
      };
}

String _formatTimestamp(int epochMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
