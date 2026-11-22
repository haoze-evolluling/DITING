part of 'rules_page.dart';

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.kind,
    required this.protected,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onProtected,
  });

  final MockRule rule;
  final RuleKind kind;

  final bool protected;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onProtected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final double opacity;
    if (protected) {
      opacity = 0.75;
    } else if (rule.enabled) {
      opacity = 1.0;
    } else {
      opacity = 0.5;
    }
    final pattern = rule.target == null
        ? rule.pattern
        : '${rule.pattern} → ${rule.target}';
    return Opacity(
      opacity: opacity,
      child: ListItem(
        leading: Icon(
          glyphByName(kind.glyphName),
          size: 20,
          color: protected ? colorScheme.onSurfaceVariant : colorScheme.primary,
        ),
        title: Text(
          pattern,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextRole.rowTitle
              .of(context)
              .copyWith(fontFeatures: appTabularFigures),
        ),
        subtitle: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (rule.important)
              TonalChip(
                label: context.l10n.ruleImportant,
                color: colorScheme.warningContainer,
                foregroundColor: colorScheme.onWarningContainer,
              ),
            if (rule.group case final group?) MetaChip(label: group),
            if (rule.subscriptionName case final name?) MetaChip(label: name),
            if (protected) MetaChip(label: context.l10n.ruleReadOnly),
            Text(
              rule.source.label(context.l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextRole.supportingText.of(context),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            CommonSwitch(
              value: rule.enabled,
              onChanged: protected ? null : onToggle,
            ),
            CommonPopupBox(
              targetBuilder: (open) => IconButton(
                tooltip: UiLocalizations.of(context).more,
                onPressed: protected ? onProtected : open,
                icon: const Icon(TablerIcons.dots),
              ),
              popupBuilder: (_) => CommonPopupMenu(
                items: [
                  CommonPopupMenuItem(
                    label: context.l10n.ruleEdit,
                    glyph: TablerIcons.pencil,
                    onPressed: onEdit,
                  ),
                  CommonPopupMenuItem(
                    label: context.l10n.ruleDelete,
                    glyph: TablerIcons.trash,
                    danger: true,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
        onTap: protected ? onProtected : null,
      ),
    );
  }
}
