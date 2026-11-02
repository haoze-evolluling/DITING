part of 'subscriptions_page.dart';

/// Group management sheet: rename and delete the groups created on this page. Deleting only
/// ungroups the subscriptions, because a group is a filter, not an owner of the rows.
class _GroupManageSheet extends ConsumerWidget {
  const _GroupManageSheet();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _askName(context, title: context.l10n.subsNewGroupTitle);
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
    final name = await _askName(
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
      // The unique index on the name rejects the update; say so instead of doing nothing.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.subsGroupDuplicate),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SubscriptionGroupRecord group,
  ) async {
    final localizations = UiLocalizations.of(context);
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.subsGroupDeleteTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.subsGroupDeleteMessage(group.name)),
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(subscriptionActionsProvider).deleteGroup(group.id);
    // The filter would point at a row that no longer exists, so fall back to "all".
    if (ref.read(subscriptionGroupFilterProvider) == group.id) {
      ref.read(subscriptionGroupFilterProvider.notifier).select(null);
    }
  }

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    String value = '',
  }) {
    return showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: title,
        value: value,
        validator: (value) => (value ?? '').trim().isEmpty
            ? context.l10n.subsGroupNameRequired
            : null,
      ),
    );
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
              padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else
            generateSection(
              items: [
                if (groups.isEmpty)
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.layers, size: 20),
                    title: Text(context.l10n.subsGroupsEmpty),
                    subtitle: Text(context.l10n.subsGroupsEmptyHint),
                  )
                else
                  for (final group in groups)
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.layers, size: 20),
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
