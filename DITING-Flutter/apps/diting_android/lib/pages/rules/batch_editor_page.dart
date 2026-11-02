import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/state/rules_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Batch import: one large text field, live parse counts, one submit button. No file
/// picker: the demo has no filesystem permission and real usage mostly pastes copied rules.
class BatchEditorPage extends ConsumerStatefulWidget {
  const BatchEditorPage({super.key});

  @override
  ConsumerState<BatchEditorPage> createState() => _BatchEditorPageState();
}

class _BatchEditorPageState extends ConsumerState<BatchEditorPage> {
  final _controller = TextEditingController();

  /// Target table. Defaults to block, since most bulk imports are block rules.
  var _kind = RuleKind.block;

  @override
  void initState() {
    super.initState();
    // Listen to the controller rather than using onChanged: paste, undo and the clear
    // button all bypass onChanged but still notify the controller.
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  RuleLineParseResult get _parsed => parseRuleLines(
    _controller.text,
    existing: {
      for (final rule in ref.read(rulesOfKindProvider(_kind))) rule.pattern,
    },
  );

  Future<void> _submit() async {
    final parsed = _parsed;
    if (parsed.accepted.isEmpty) {
      return;
    }
    final count = await ref
        .read(rulesProvider.notifier)
        .importRules(_kind, parsed.accepted);
    _controller.clear();
    if (!mounted) {
      return;
    }
    await showFloatingDialog<void>(
      context: context,
      child: CommonDialog(
        title: context.l10n.batchImportDone,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(UiLocalizations.of(context).submit),
          ),
        ],
        child: Text(_reportText(count: count, parsed: parsed)),
      ),
    );
    if (!mounted) {
      return;
    }
    // Leave once imported: the user came only to paste a block of rules.
    context.pop();
  }

  String _reportText({
    required int count,
    required RuleLineParseResult parsed,
  }) {
    final lines = <String>[
      context.l10n.ruleBatchImported(_kind.title(context.l10n), count),
    ];
    if (parsed.duplicated.isNotEmpty) {
      lines.add(
        context.l10n.ruleBatchSkippedDuplicates(parsed.duplicated.length),
      );
    }
    if (parsed.rejected.isNotEmpty) {
      lines.add(
        context.l10n.ruleBatchAllowRejected(parsed.rejected.length),
      );
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    final colorScheme = context.colorScheme;
    final canSubmit = parsed.accepted.isNotEmpty;

    return CommonScaffold(
      title: context.l10n.batchAddTitle,
      resizeToAvoidBottomInset: true,
      // The app bar floats over the body, so the body reserves status bar plus toolbar
      // height or the section header would be drawn underneath it.
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8 + context.appBarInset, 16, 16),
        children: [
          // Target table above the text field: pick where first, then paste.
          // padding is zero because this ListView already pads 16 horizontally.
          generateSection(
            padding: EdgeInsets.zero,
            title: context.l10n.batchTarget,
            items: [
              ListItem<RuleKind>.options(
                title: Text(context.l10n.batchTargetTable),
                subtitle: Text(context.l10n.batchTargetTableSubtitle),
                options: RuleKind.values,
                value: _kind,
                textBuilder: (kind) => kind.title(context.l10n),
                onChanged: (kind) => setState(() => _kind = kind),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fixed height 360 shows a screenful without pushing the button off-screen.
          // borderRadius must be explicit: FilledInputTheme defaults to AppRadius.full.
          SizedBox(
            height: 360,
            child: FilledInputTheme(
              borderRadius: AppRadius.lg,
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: appMonospaceFontFamily,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: context.l10n.batchPlaceholder,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Parse counts sit right under the text field: they explain the pasted content,
          // and the further away they are the less they look related to it.
          CommonCard(
            child: StatStrip(
              stats: [
                StatItem(
                  label: context.l10n.batchImportable,
                  value: '${parsed.accepted.length}',
                  color: colorScheme.success,
                ),
                StatItem(
                  label: context.l10n.batchDuplicated,
                  value: '${parsed.duplicated.length}',
                  color: colorScheme.warning,
                ),
                StatItem(
                  label: context.l10n.batchInvalid,
                  value: '${parsed.rejected.length}',
                  color: parsed.rejected.isEmpty
                      ? null
                      : colorScheme.destructive,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Submit sits at the end of the body, not the app bar: the item count is the last
          // confirmation point before the user commits, and an icon cannot show it.
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: Text(
                context.l10n.ruleBatchImportCount(parsed.accepted.length),
              ),
            ),
          ),
          if (parsed.rejected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CommonCard(
                isError: true,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: [
                      Row(
                        spacing: 6,
                        children: [
                          GlyphIcon(
                            AppGlyphs.warning,
                            size: 16,
                            color: colorScheme.error,
                          ),
                          Text(context.l10n.batchInvalidHeader, style: context.listTitleStyle),
                        ],
                      ),
                      for (final line in parsed.rejected.take(5))
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.listCaptionStyle.copyWith(
                            fontFamily: appMonospaceFontFamily,
                          ),
                        ),
                      Text(
                        context.l10n.ruleAllowNeedsAllowlist,
                        style: context.listCaptionStyle.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (parsed.duplicated.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CommonCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(context.l10n.batchDuplicateHeader, style: context.listTitleStyle),
                      for (final line in parsed.duplicated.take(3))
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.listCaptionStyle.copyWith(
                            fontFamily: appMonospaceFontFamily,
                          ),
                        ),
                      if (parsed.duplicated.length > 3)
                        Text(
                          context.l10n.ruleBatchMoreDuplicates(
                            parsed.duplicated.length,
                          ),
                          style: context.listCaptionStyle,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const DockSpacer(),
        ],
      ),
    );
  }
}
