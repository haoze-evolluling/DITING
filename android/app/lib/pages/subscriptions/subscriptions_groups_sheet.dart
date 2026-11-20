part of 'subscriptions_page.dart';

class _GroupManageSheet extends ConsumerWidget {
  const _GroupManageSheet();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _askGroupName(
      context,
      title: context.l10n.subsNewGroupTitle,
    );
    if (name == null) {
      return;
    }
    await ref.read(subscriptionActionsProvider).createGroup(name);
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    SubscriptionGroupRecord group,
  ) async {
    final name = await _askGroupName(
      context,
      title: context.l10n.subsGroupRenameTitle,
      value: group.name,
    );
    if (name == null) {
      return;
    }
    final ok = await ref
        .read(subscriptionActionsProvider)
        .renameGroup(group.id, name);
    if (!ok && context.mounted) {
      showAppSnack(context, context.l10n.subsGroupDuplicate);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SubscriptionGroupRecord group,
  ) async {
    final confirmed = await _confirm(
      context,
      title: context.l10n.subsGroupDeleteTitle,
      message: context.l10n.subsGroupDeleteMessage(group.name),
      confirmLabel: context.l10n.commonDelete,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(subscriptionActionsProvider).deleteGroup(group.id);
    if (ref.read(subscriptionGroupFilterProvider) == group.id) {
      ref.read(subscriptionGroupFilterProvider.notifier).select(null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(subscriptionGroupsProvider).value;
    final entries = ref.watch(subscriptionEntriesProvider).value ?? const [];
    return CommonScaffold(
      title: context.l10n.subsManageGroupsTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.subsNewGroupTitle,
          onPressed: () => _create(context, ref),
        ),
      ],
      body: PageBody(
        children: [
          if (groups == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else
            generateSection(
              title: context.l10n.subsGroupsList,
              items: [
                if (groups.isEmpty)
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.folder, size: 20),
                    title: Text(context.l10n.subsGroupsEmpty),
                    subtitle: Text(context.l10n.subsGroupsEmptyHint),
                  )
                else
                  for (final group in groups)
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.folder, size: 20),
                      title: Text(group.name),
                      subtitle: Text(
                        context.l10n.subsGroupSubCount(
                          entries
                              .where(
                                (entry) => entry.record.groupId == group.id,
                              )
                              .length,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: context.l10n.commonEdit,
                            onPressed: () => _rename(context, ref, group),
                            icon: const GlyphIcon(AppGlyphs.edit, size: 20),
                          ),
                          IconButton(
                            tooltip: context.l10n.commonDelete,
                            onPressed: () => _delete(context, ref, group),
                            icon: const GlyphIcon(AppGlyphs.delete, size: 20),
                          ),
                        ],
                      ),
                    ),
              ],
              footer: context.l10n.subsGroupsFooter,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
