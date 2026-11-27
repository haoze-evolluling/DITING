part of 'server_filter_subscriptions_page.dart';

class _ServerSubscriptionCard extends StatelessWidget {
  const _ServerSubscriptionCard({
    required this.list,
    required this.updating,
    required this.busy,
    required this.onToggle,
    required this.onUpdate,
    required this.onRename,
    required this.onDelete,
    required this.onEdit,
  });

  final ServerFilterList list;
  final bool updating;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onUpdate;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final hasError = list.hasError;
    return CommonCard(
      isError: hasError,
      child: Opacity(
        opacity: list.enabled ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListItem(
              leading: Icon(
                list.isRemote ? TablerIcons.cloud_network : TablerIcons.file_import,
                size: 20,
                color: hasError ? scheme.error : scheme.primary,
              ),
              title: Text(
                list.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.rowTitle.of(context),
              ),
              subtitle: Text(
                serverListSubtitle(list, context.l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.supportingText.of(context),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  CommonSwitch(value: list.enabled, onChanged: onToggle),
                  CommonPopupBox(
                    targetBuilder: (open) => IconButton(
                      tooltip: UiLocalizations.of(context).more,
                      onPressed: open,
                      icon: const Icon(TablerIcons.dots),
                    ),
                    popupBuilder: (_) => CommonPopupMenu(
                      items: [
                        CommonPopupMenuItem(
                          label: list.isRemote
                              ? context.l10n.subsUpdateNow
                              : context.l10n.subsReimport,
                          glyph: TablerIcons.refresh,
                          onPressed: busy ? null : onUpdate,
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.subsEdit,
                          glyph: TablerIcons.adjustments,
                          onPressed: onEdit,
                        ),
                        CommonPopupMenuItem(
                          label: context.l10n.subsRename,
                          glyph: TablerIcons.pencil,
                          onPressed: onRename,
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
              onTap: onEdit,
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
                      MetaChip(
                        label: context.l10n.subsRuleCountValue(
                          serverRuleCountLabel(list.rulesCount),
                        ),
                      ),
                      MetaChip(
                        label: serverListUpdatedLabel(list, context.l10n),
                      ),
                      if (list.isCached)
                        MetaChip(
                          label: context.l10n.subscriptionHealthCached,
                        ),
                      if (list.mirrorTemplate.isNotEmpty)
                        MetaChip(
                          label: list.mirrorFallback
                              ? context.l10n.subsMirrorFallbackShort
                              : context.l10n.subsMirrorNoFallback,
                        ),
                    ],
                  ),
                  Text(
                    serverListDisplayTarget(list),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextRole.supportingText
                        .of(context)
                        .copyWith(fontFeatures: appTabularFigures),
                  ),
                  if (list.mirrorTemplate.isNotEmpty)
                    Text(
                      context.l10n.subsMirrorName(list.mirrorTemplate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextRole.supportingText.of(context),
                    ),
                  if (hasError)
                    Row(
                      spacing: 6,
                      children: [
                        Icon(
                          TablerIcons.alert_circle,
                          size: 16,
                          color: scheme.error,
                        ),
                        Expanded(
                          child: Text(
                            list.lastError,
                            style: AppTextRole.supportingText
                                .of(context)
                                .copyWith(color: scheme.error),
                          ),
                        ),
                      ],
                    ),
                  if (updating)
                    LinearProgressIndicator(
                      minHeight: 3,
                      borderRadius: AppRadius.standard,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerGroupSheet extends ConsumerWidget {
  const _ServerGroupSheet({required this.onRename, required this.onDelete});

  final Future<bool> Function(String from, String to) onRename;
  final Future<void> Function(String group) onDelete;

  Future<void> _rename(BuildContext context, String group) async {
    final name = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: context.l10n.subsGroupRenameTitle,
        value: group,
        validator: (value) =>
            (value ?? '').trim().isEmpty ? context.l10n.subsGroupNameRequired : null,
      ),
    );
    if (name == null || !context.mounted) return;
    final ok = await onRename(group, name);
    if (!ok && context.mounted) {
      showAppSnack(context, context.l10n.subsGroupDuplicate);
    }
  }

  Future<void> _delete(BuildContext context, String group) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.subsGroupDeleteTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.subsGroupDeleteMessage(group)),
      ),
    );
    if (confirmed == true) {
      await onDelete(group);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(serverControllerProvider).value?.config;
    final seen = <String>{};
    for (final list in config?.filter.lists ?? const <ServerFilterList>[]) {
      if (list.group.isNotEmpty) seen.add(list.group);
    }
    final groups = seen.toList()..sort();
    return CommonScaffold(
      title: context.l10n.subsManageGroupsTitle,
      body: ListView(
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          generateSection(
            title: context.l10n.subsGroupsList,
            items: [
              if (groups.isEmpty)
                ListItem(
                  leading: const Icon(TablerIcons.info_circle, size: 20),
                  title: Text(context.l10n.subsGroupsEmpty),
                ),
              for (final group in groups)
                ListItem(
                  leading: const Icon(TablerIcons.folder, size: 20),
                  title: Text(group),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: context.l10n.subsGroupRenameTitle,
                        onPressed: () => _rename(context, group),
                        icon: const Icon(TablerIcons.pencil, size: 18),
                      ),
                      IconButton(
                        tooltip: context.l10n.subsGroupDeleteTitle,
                        onPressed: () => _delete(context, group),
                        icon: const Icon(TablerIcons.trash, size: 18),
                      ),
                    ],
                  ),
                ),
            ],
            footer: context.l10n.subsGroupsFooter,
          ),
        ],
      ),
    );
  }
}
