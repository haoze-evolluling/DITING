import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';

import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/state/rules_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_list_view.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:diting_android/widgets/empty_state.dart';
import 'package:diting_android/widgets/glyph_lookup.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'rules_dialogs.dart';
part 'rules_rows.dart';

/// Search debounce, 250 ms like all three upstream rule tables: slower makes live
/// filtering pointless, faster rebuilds the whole list on every keystroke.
const _searchDebounce = Duration(milliseconds: 250);

/// Rule page: block, allow and rewrite share one skeleton, differing only in title, stats
/// and row content, matching the single upstream RuleListScreen with a dataset parameter.
class RulesPage extends ConsumerStatefulWidget {
  const RulesPage({super.key, required this.kind});

  final String kind;

  @override
  ConsumerState<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends ConsumerState<RulesPage> {
  late final _search = TextEditingController();
  Timer? _debounce;

  /// Debounced keyword. The text field itself is not debounced, or typing would lag.
  var _query = '';
  RuleSourceFilter _sourceFilter;

  RuleKind get _kind => switch (widget.kind) {
    'allow' => RuleKind.allow,
    'rewrite' => RuleKind.rewrite,
    _ => RuleKind.block,
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (!mounted) {
        return;
      }
      setState(() => _query = value.trim().toLowerCase());
    });
  }

  /// Prompt once for pattern plus optional target; rewrite needs two fields, which is what
  /// _RuleDialog exists for.
  Future<({String pattern, String? target})?> _promptRule({
    required String title,
    required String initialPattern,
    String? initialTarget,
    Set<String> existingPatterns = const {},
  }) async {
    final kind = _kind;
    if (kind != RuleKind.rewrite) {
      final pattern = await showFloatingDialog<String>(
        context: context,
        child: InputDialog(
          title: title,
          value: initialPattern,
          hintText: context.l10n.rulePatternHint,
          selectAll: initialPattern.isNotEmpty,
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) {
              return context.l10n.rulePatternRequired;
            }
            if (kind != RuleKind.allow && text.contains('#@#')) {
              return context.l10n.ruleAllowNeedsAllowlist;
            }
            if (existingPatterns.contains(text)) {
              return context.l10n.ruleAlreadyExists;
            }
            return null;
          },
        ),
      );
      return pattern == null ? null : (pattern: pattern.trim(), target: null);
    }
    return showFloatingDialog<({String pattern, String? target})>(
      context: context,
      child: _RuleDialog(
        title: title,
        initialPattern: initialPattern,
        initialTarget: initialTarget,
        existingPatterns: existingPatterns,
      ),
    );
  }

  Future<void> _addRule() async {
    final kind = _kind;
    final result = await _promptRule(
      title: context.l10n.ruleAddForKind(kind.title(context.l10n)),
      initialPattern: '',
      existingPatterns: {
        for (final rule in ref.read(rulesOfKindProvider(kind))) rule.pattern,
      },
    );
    if (result == null || !mounted) {
      return;
    }
    await ref
        .read(rulesProvider.notifier)
        .add(kind, result.pattern, target: result.target);
  }

  Future<void> _editRule(MockRule rule) async {
    final kind = _kind;
    final result = await _promptRule(
      title: rule.source == RuleSource.preset
          ? context.l10n.ruleEditDefaultPreset
          : context.l10n.ruleEditForKind(kind.title(context.l10n)),
      initialPattern: rule.pattern,
      initialTarget: rule.target,
      existingPatterns: {
        for (final other in ref.read(rulesOfKindProvider(kind)))
          if (other.id != rule.id) other.pattern,
      },
    );
    if (result == null || !mounted) {
      return;
    }
    await ref
        .read(rulesProvider.notifier)
        .edit(kind, rule.id, result.pattern, target: result.target);
  }

  Future<void> _deleteRule(MockRule rule) async {
    final kind = _kind;
    final confirmed = await _confirm(
      context,
      title: context.l10n.ruleDelete,
      message: switch (rule.source) {
        RuleSource.preset => context.l10n.ruleDeletePresetMessage(rule.pattern),
        RuleSource.subscription =>
          context.l10n.ruleDeleteSubscriptionMessage(
            rule.pattern,
            rule.subscriptionName ?? context.l10n.ruleSourceSubscription,
          ),
        RuleSource.user => context.l10n.ruleDeleteUserMessage(rule.pattern),
      },
      confirmLabel: context.l10n.formDelete,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await ref.read(rulesProvider.notifier).remove(kind, rule.id);
  }

  Future<void> _clearCustom() async {
    final kind = _kind;
    final confirmed = await _confirm(
      context,
      title: context.l10n.ruleClearCustomTitle,
      message: context.l10n.ruleClearCustomMessage(kind.title(context.l10n)),
      confirmLabel: context.l10n.commonClearAll,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await ref.read(rulesProvider.notifier).clearCustom(kind);
  }

  Future<void> _resetPreset() async {
    final kind = _kind;
    final confirmed = await _confirm(
      context,
      title: context.l10n.ruleResetDefault,
      message: context.l10n.ruleResetMessage,
      confirmLabel: context.l10n.commonReset,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await ref.read(rulesProvider.notifier).resetPreset(kind);
  }

  /// Hint when a read-only row is tapped. A dialog rather than a snackbar: the
  /// message tells the user where to enable editing and must not scroll away.
  Future<void> _showProtectedHint() => showFloatingDialog<void>(
    context: context,
    child: CommonDialog(
      title: context.l10n.rulePresetProtectedTitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(UiLocalizations.of(context).close),
        ),
      ],
      child: Text(
        context.l10n.rulePresetProtectedMessage,
      ),
    ),
  );

  Future<void> _togglePresetEditing(bool value) async {
    if (!value) {
      ref.read(allowPresetEditableProvider.notifier).set(false);
      return;
    }
    final confirmed = await _confirm(
      context,
      title: context.l10n.ruleAllowEditTitle,
      message:
          context.l10n.ruleAllowEditMessage,
      confirmLabel: context.l10n.ruleAllowEditConfirm,
    );
    if (!confirmed || !mounted) {
      return;
    }
    ref.read(allowPresetEditableProvider.notifier).set(true);
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final allowPresetEditable = ref.watch(allowPresetEditableProvider);
    final filter = RuleListFilter(
      kind: kind,
      source: _sourceFilter,
      query: _query,
    );
    // Both come from providers, so the counter and the rows always describe the same snapshot.
    final tally = ref.watch(ruleListTallyProvider(filter));
    final visible = ref.watch(filteredRulesProvider(filter));
    final searching = _query.isNotEmpty || _sourceFilter != null;

    return CommonScaffold(
      title: kind.title(context.l10n),
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.ruleAddForKind(kind.title(context.l10n)),
          onPressed: _addRule,
        ),
        IconButtonData(
          glyph: AppGlyphs.listAdd,
          tooltip: context.l10n.batchAddTitle,
          onPressed: () => context.push(Routes.batchEditor),
        ),
      ],
      menuItems: [
        CommonPopupMenuItem(
          label: context.l10n.ruleClearCustomForKind(
            kind.title(context.l10n),
          ),
          glyph: AppGlyphs.broom,
          danger: true,
          onPressed: tally.custom == 0 ? null : _clearCustom,
        ),
        if (kind == RuleKind.allow)
          CommonPopupMenuItem(
            label: context.l10n.ruleResetDefault,
            glyph: AppGlyphs.reset,
            onPressed: _resetPreset,
          ),
      ],
      body: AppListScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: CommonCard(
                    child: StatStrip(
                      stats: [
                        StatItem(label: context.l10n.ruleTotal, value: '${tally.total}'),
                        StatItem(
                          label: context.l10n.ruleEnabled,
                          value: '${tally.enabled}',
                          color: context.colorScheme.success,
                        ),
                        StatItem(
                          label: kind == RuleKind.rewrite ? context.l10n.ruleRewriteEntries : context.l10n.ruleCustom,
                          value: '${tally.custom}',
                        ),
                      ],
                    ),
                  ),
                ),
                if (kind == RuleKind.allow)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: CommonCard(
                      child: ListItem.toggle(
                        title: Text(context.l10n.ruleAllowEditDefault),
                        subtitle: Text(context.l10n.ruleAllowEditDefaultSubtitle),
                        value: allowPresetEditable,
                        onChanged: _togglePresetEditing,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SearchField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: _SourceChips(
                    value: _sourceFilter,
                    onChanged: (value) => setState(() => _sourceFilter = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text(
                    // The counter always reports a number, even zero: the empty state already
                    // says there are no matching rules, and repeating it reads as double render.
                    context.l10n.ruleTally(tally.matched, tally.matchedEnabled),
                    style: context.listCaptionStyle,
                  ),
                ),
              ],
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: EmptyStateBox(
                minHeight: 320,
                child: NullStatus(
                  label: searching
                      ? context.l10n.ruleNoMatch
                      : context.l10n.ruleNoRulesForKind(
                          kind.title(context.l10n),
                        ),
                  description: searching ? context.l10n.ruleNoMatchDescription : kind.summary(context.l10n),
                  illustration: NullStatusIllustration.rules,
                  action: searching
                      ? null
                      : FilledButton(
                          onPressed: _addRule,
                          child: Text(
                            context.l10n.ruleAddForKind(
                              kind.title(context.l10n),
                            ),
                          ),
                        ),
                ),
              ),
            )
          else
            // One sliver per source section, each a lazy SliverList: a subscription with a
            // hundred thousand rows used to be inflated in one frame and froze the UI.
            for (final section in ruleSections(visible))
              ...ruleSectionSlivers(
                source: section.source,
                rules: section.rules,
                kind: kind,
                allowPresetEditable: allowPresetEditable,
                l10n: context.l10n,
                onToggle: (rule, enabled) => ref
                    .read(rulesProvider.notifier)
                    .toggle(kind, rule.id, enabled),
                onEdit: _editRule,
                onDelete: _deleteRule,
                onProtected: _showProtectedHint,
              ),
        ],
      ),
    );
  }
}

/// Source filter chips: all, user, subscription, built-in preset. This row is the reference
/// chip-row shape for the whole app, now extracted into ChipRow plus FilterPill.
class _SourceChips extends StatelessWidget {
  const _SourceChips({required this.value, required this.onChanged});

  final RuleSourceFilter value;
  final ValueChanged<RuleSourceFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(RuleSourceFilter, String)>[
      (null, context.l10n.ruleAll),
      for (final source in RuleSource.values) (source, source.label(context.l10n)),
    ];
    return ChipRow(
      children: [
        for (final (source, label) in options)
          FilterPill(
            label: label,
            selected: source == value,
            onPressed: () => onChanged(source),
          ),
      ],
    );
  }
}

/// Rule rows grouped by source, in enum order. Presets may be read-only and subscriptions get
/// overwritten, so grouping carries meaning and each group is its own sliver.
class RuleSection {
  const RuleSection(this.source, this.rules);

  final RuleSource source;
  final List<MockRule> rules;
}

List<RuleSection> ruleSections(List<MockRule> rules) {
  final bySource = <RuleSource, List<MockRule>>{};
  for (final rule in rules) {
    (bySource[rule.source] ??= []).add(rule);
  }
  return [
    for (final source in RuleSource.values)
      if (bySource[source] case final group?) RuleSection(source, group),
  ];
}

/// Header plus a lazy row sliver for one source group. Rows are built on demand: a subscription
/// can carry six figures of rules, and inflating them all in the first frame is what froze the
/// page (see the 2026-10-27 ANR with 191,090 rules).
List<Widget> ruleSectionSlivers({
  required RuleSource source,
  required List<MockRule> rules,
  required RuleKind kind,
  required bool allowPresetEditable,
  required void Function(MockRule rule, bool enabled) onToggle,
  required ValueChanged<MockRule> onEdit,
  required ValueChanged<MockRule> onDelete,
  required VoidCallback onProtected,
  required AppL10n l10n,
}) {
  return [
    SliverToBoxAdapter(child: ListHeader(title: source.label(l10n))),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: rules.length,
        // Rows are cheap to rebuild; keeping thousands alive is what made the old list stutter.
        addAutomaticKeepAlives: false,
        itemBuilder: (context, index) {
          final rule = rules[index];
          return ItemPositionProvider(
            position: ItemPosition.get(index, rules.length),
            child: _RuleRow(
              rule: rule,
              kind: kind,
              protected: isRuleProtected(
                rule,
                kind: kind,
                allowPresetEditable: allowPresetEditable,
              ),
              onToggle: (enabled) => onToggle(rule, enabled),
              onEdit: () => onEdit(rule),
              onDelete: () => onDelete(rule),
              onProtected: onProtected,
            ),
          );
        },
      ),
    ),
  ];
}
