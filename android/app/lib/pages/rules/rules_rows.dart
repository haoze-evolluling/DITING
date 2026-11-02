part of 'rules_page.dart';

/// One rule row, organized like the upstream RuleItem: main line is the rule (rewrite shows
/// `pattern -> target`), second line the source label, shown as text because names are long.
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

  /// Read-only protection: a preset row while editing default whitelists is off.
  final bool protected;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onProtected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    // Read-only rows drop to 0.75 opacity and disabled rows further still: the two
    // "cannot press" states must be distinguishable, or the switch looks broken.
    final opacity = protected ? 0.75 : (rule.enabled ? 1.0 : 0.5);
    final pattern = rule.target == null
        ? rule.pattern
        : '${rule.pattern} → ${rule.target}';
    return Opacity(
      opacity: opacity,
      child: ListItem(
        leading: GlyphIcon(
          glyphByName(kind.glyphName),
          size: 20,
          color: protected ? colorScheme.onSurfaceVariant : colorScheme.primary,
        ),
        title: Text(
          pattern,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.listTitleStyle.copyWith(
            fontFamily: appMonospaceFontFamily,
            fontSize: 15,
          ),
        ),
        // The subtitle holds four chips plus the source label, and ListTile leaves about 160px on
        // a 320-wide device, while chips cannot shrink. A Row used to overflow here.
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
              style: context.listCaptionStyle,
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
                icon: const GlyphIcon(AppGlyphs.more),
              ),
              popupBuilder: (_) => CommonPopupMenu(
                items: [
                  CommonPopupMenuItem(
                    label: context.l10n.ruleEdit,
                    glyph: AppGlyphs.edit,
                    onPressed: onEdit,
                  ),
                  CommonPopupMenuItem(
                    label: context.l10n.ruleDelete,
                    glyph: AppGlyphs.delete,
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
