/// The custom rule editor and the AdGuard syntax guide beside it.
///
/// The old desktop console's `RulesPanel.vue` "custom" tab is the blueprint. The text is edited
/// locally; only the save button posts it, and the page then adopts the list the service re-reads.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_custom_rules_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The non-empty lines of the editor, the shape the service's list takes.
List<String> desktopCustomRuleLines(String text) => [
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

class CustomRulesEditorCard extends ConsumerStatefulWidget {
  const CustomRulesEditorCard({super.key});

  @override
  ConsumerState<CustomRulesEditorCard> createState() =>
      _CustomRulesEditorCardState();
}

class _CustomRulesEditorCardState extends ConsumerState<CustomRulesEditorCard> {
  final _text = TextEditingController();
  String? _adopted;

  /// Set as soon as the text is typed: a rejected save must leave the draft alone, because the
  /// service still holds the old list and adopting it would discard the edit.
  bool _dirty = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Adopts the service's list only when its text changes, never on an ordinary rebuild, so a
  /// rejected save or a poll cannot overwrite what is being typed.
  void _adopt(List<String> rules) {
    if (_dirty) return;
    final text = rules.join('\n');
    if (_adopted == text) return;
    _adopted = text;
    _text.text = text;
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final lines = desktopCustomRuleLines(_text.text);
    final error = await ref
        .read(desktopCustomRulesProvider.notifier)
        .save(lines);
    if (!mounted) return;
    if (error == null) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopFilterRulesSaved
          : l10n.desktopFilterRulesSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopCustomRulesProvider);
    if (state.loaded) _adopt(state.rules);
    return DashboardCard(
      semanticLabel: l10n.desktopFilterRulesEditorTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.edit,
            title: l10n.desktopFilterRulesEditorTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopFilterRulesLineCount(
                  desktopCustomRuleLines(_text.text).length,
                ),
              ),
            ],
            trailing: [
              if (state.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardIconButton(
                  glyph: AppGlyphs.check,
                  tooltip: l10n.desktopFilterRulesSave,
                  onPressed: state.loaded ? () => unawaited(_save()) : null,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopFilterRulesEditorBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (!state.loaded)
            _Unavailable(
              loading: state.isLoading,
              error: state.error,
              onRetry: ref.read(desktopCustomRulesProvider.notifier).reload,
            )
          else ...[
            TextField(
              controller: _text,
              minLines: 14,
              maxLines: 24,
              keyboardType: TextInputType.multiline,
              style: AppTextStyle.callout.of(context).toMonospace,
              decoration: InputDecoration(
                hintText: l10n.desktopFilterRulesPlaceholder,
              ),
              onChanged: (_) => setState(() => _dirty = true),
            ),
            const SizedBox(height: 10),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Text(
                    l10n.desktopFilterRulesHint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.label(context),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: state.saving ? null : () => unawaited(_save()),
                  icon: const GlyphIcon(AppGlyphs.check, size: 16),
                  label: Text(
                    state.saving
                        ? l10n.desktopFilterRulesSaving
                        : l10n.desktopFilterRulesSave,
                  ),
                ),
              ],
            ),
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.desktopFilterRulesSaveFailed(state.error!.message),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.label(
                  context,
                  color: context.colorScheme.error,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The five rule shapes the console documents. The code strings are DNS syntax, so they stay out of
/// the ARB; the surrounding words do not.
class RuleSyntaxGuideCard extends StatelessWidget {
  const RuleSyntaxGuideCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = [
      (
        title: l10n.desktopFilterGuideDomainTitle,
        tag: l10n.desktopFilterGuideCommon,
        code: '||example.com^',
        body: l10n.desktopFilterGuideDomainBody,
      ),
      (
        title: l10n.desktopFilterGuideAllowTitle,
        tag: l10n.desktopFilterGuideExempt,
        code: '@@||safe.com^',
        body: l10n.desktopFilterGuideAllowBody,
      ),
      (
        title: l10n.desktopFilterGuideHostsTitle,
        tag: l10n.desktopFilterGuideCompat,
        code: '0.0.0.0 bad.com',
        body: l10n.desktopFilterGuideHostsBody,
      ),
      (
        title: l10n.desktopFilterGuideImportantTitle,
        tag: l10n.desktopFilterGuidePriority,
        code: '||urgent.com^\$important',
        body: l10n.desktopFilterGuideImportantBody,
      ),
      (
        title: l10n.desktopFilterGuideRewriteTitle,
        tag: l10n.desktopFilterGuideRewrite,
        code: '||nas.lan^\$dnsrewrite=10.0.0.5',
        body: l10n.desktopFilterGuideRewriteBody,
      ),
    ];
    return DashboardCard(
      semanticLabel: l10n.desktopFilterGuideTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.info,
            title: l10n.desktopFilterGuideTitle,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopFilterGuideBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          for (final entry in entries) ...[
            _GuideBlock(entry: entry),
            const SizedBox(height: 8),
          ],
          Text(
            l10n.desktopFilterGuideFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

class _GuideBlock extends StatelessWidget {
  const _GuideBlock({required this.entry});

  final ({String title, String tag, String code, String body}) entry;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
              ),
              Text(entry.tag, style: DashboardText.label(context)),
            ],
          ),
          Text(
            entry.code,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.callout
                .of(context, emphasized: true)
                .toMonospace
                .copyWith(color: colors.series2),
          ),
          Text(entry.body, style: DashboardText.label(context)),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final DesktopApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CommonCircleLoading(size: 22)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          l10n.desktopFilterRulesLoadFailed,
          style: DashboardText.label(context),
        ),
        Text(
          error?.message ?? '',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
        FilledButton.tonal(
          onPressed: onRetry,
          child: Text(l10n.desktopRetry),
        ),
      ],
    );
  }
}
