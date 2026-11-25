part of 'subscription_edit_page.dart';

class _OtherModeImportSection extends StatelessWidget {
  const _OtherModeImportSection({
    required this.modeLabel,
    required this.snapshot,
    required this.selectedKeys,
    required this.currentKeys,
    required this.onToggle,
    required this.onSelectAll,
  });

  final String modeLabel;
  final AsyncValue<List<SubscriptionEntry>> snapshot;
  final Set<String> selectedKeys;
  final Set<String> currentKeys;
  final void Function(SubscriptionEntry entry, bool selected) onToggle;
  final ValueChanged<bool> onSelectAll;

  List<SubscriptionEntry> get _entries => snapshot.value ?? const [];

  List<SubscriptionEntry> get _available => [
    for (final entry in _entries)
      if (!currentKeys.contains(subscriptionEntryKey(entry.record))) entry,
  ];

  bool get _allSelected {
    final available = _available;
    return available.isNotEmpty &&
        available.every(
          (entry) => selectedKeys.contains(subscriptionEntryKey(entry.record)),
        );
  }

  int get _selectedCount => _available
      .where(
        (entry) => selectedKeys.contains(subscriptionEntryKey(entry.record)),
      )
      .length;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final available = _available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetCard(
          title: l10n.subsOtherModeFromMode(modeLabel),
          footer: l10n.subsOtherModeExplain(modeLabel),
          children: [
            ListItem(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: const Icon(TablerIcons.folder_symlink, size: 20),
              title: Text(l10n.subsOtherModeReady(available.length)),
              subtitle: Text(l10n.subsOtherModeSelected(_selectedCount)),
              trailing: available.isEmpty
                  ? null
                  : TonalButton(
                      size: TonalButtonSize.compact,
                      label: _allSelected
                          ? l10n.subsOtherModeClearAll
                          : l10n.subsOtherModeSelectAll,
                      onPressed: () => onSelectAll(!_allSelected),
                    ),
              onTap: available.isEmpty
                  ? null
                  : () => onSelectAll(!_allSelected),
            ),
          ],
        ),
        if (snapshot.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CommonCircleLoading()),
          )
        else if (snapshot.error case final error?)
          generateSection(
            title: l10n.subsOtherModeList,
            items: [
              ListItem(
                leading: Icon(
                  TablerIcons.alert_circle,
                  size: 20,
                  color: context.colorScheme.error,
                ),
                title: Text(l10n.subsOtherModeLoadFailed),
                subtitle: Text(
                  error.toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        else if (_entries.isEmpty)
          generateSection(
            title: l10n.subsOtherModeList,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.info_circle, size: 20),
                title: Text(l10n.subsOtherModeEmptyTitle(modeLabel)),
                subtitle: Text(l10n.subsOtherModeEmptyBody(modeLabel)),
              ),
            ],
          )
        else
          generateSection(
            title: l10n.subsOtherModeList,
            items: [
              if (available.isEmpty)
                ListItem(
                  leading: Icon(
                    TablerIcons.circle_check,
                    size: 20,
                    color: context.colorScheme.success,
                  ),
                  title: Text(l10n.subsOtherModeAllImported),
                ),
              for (final entry in _entries)
                _ImportEntryRow(
                  entry: entry,
                  alreadyImported: currentKeys.contains(
                    subscriptionEntryKey(entry.record),
                  ),
                  selected: selectedKeys.contains(
                    subscriptionEntryKey(entry.record),
                  ),
                  onToggle: (selected) => onToggle(entry, selected),
                ),
            ],
          ),
      ],
    );
  }
}

class _ImportEntryRow extends StatelessWidget {
  const _ImportEntryRow({
    required this.entry,
    required this.alreadyImported,
    required this.selected,
    required this.onToggle,
  });

  final SubscriptionEntry entry;
  final bool alreadyImported;
  final bool selected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final record = entry.record;
    return ListItem.checkbox(
      key: ValueKey(subscriptionEntryKey(record)),
      value: selected,
      onChanged: alreadyImported ? null : (value) => onToggle(value ?? false),
      leading: Icon(
        record.isRemote ? TablerIcons.cloud_network : TablerIcons.file_import,
        size: 20,
        color: alreadyImported
            ? colorScheme.onSurfaceVariant
            : colorScheme.primary,
      ),
      title: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (alreadyImported)
            TonalChip(
              label: l10n.subsOtherModeAlready,
              color: context.raisedSurfaceLevel.colorOf(colorScheme),
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
        ],
      ),
      subtitle: Text(
        '${entry.groupKey} · ${record.kind.displayName(l10n)}'
        ' · ${l10n.subsRuleCountValue('${entry.ruleCount}')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
