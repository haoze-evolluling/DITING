/// The rule simulator sub-page: enter a domain, pick a record type, and read the service's verdict.
///
/// The old desktop console's `RuleTestPanel.vue` is the blueprint. The verdict, the matched rule, the
/// list it came from and any `$dnsrewrite` answer all come from `/filter/check`; the page only names
/// them.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_rule_check_models.dart';
import 'package:diting_desktop/data/api/desktop_rule_check_providers.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_desktop/widgets/desktop_picker.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const List<String> _qtypes = ['A', 'AAAA', 'ANY'];
const List<String> _examples = [
  'adservice.google.com',
  'telemetry.microsoft.com',
  'baidu.com',
];

/// The console's `RCODE_NAMES`; the service returns the numeric code only.
String desktopRcodeName(int rcode) => switch (rcode) {
  0 => 'NOERROR',
  1 => 'FORMERR',
  2 => 'SERVFAIL',
  3 => 'NXDOMAIN',
  4 => 'NOTIMP',
  5 => 'REFUSED',
  _ => 'RCODE $rcode',
};

class DesktopRuleCheckPage extends ConsumerStatefulWidget {
  const DesktopRuleCheckPage({super.key});

  static const path = '/hub/rule-test';

  @override
  ConsumerState<DesktopRuleCheckPage> createState() =>
      _DesktopRuleCheckPageState();
}

class _DesktopRuleCheckPageState extends ConsumerState<DesktopRuleCheckPage> {
  final _domain = TextEditingController();
  String _qtype = _qtypes.first;

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  void _run() {
    final domain = _domain.text.trim();
    if (domain.isEmpty) return;
    unawaited(
      ref.read(desktopRuleCheckProvider.notifier).check(domain, _qtype),
    );
  }

  void _fill(String domain) {
    _domain.text = domain;
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopRuleCheckProvider);
    return CommonScaffold(
      title: l10n.desktopToolsRulePageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopToolsRuleRun,
          onPressed: state.running ? null : _run,
          icon: state.running
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.bolt),
        ),
      ],
      body: PageBody(
        children: [
          DesktopCardBoard(
            cards: [
              _InputCard(
                domain: _domain,
                qtype: _qtype,
                running: state.running,
                onQtype: (value) => setState(() => _qtype = value),
                onRun: _run,
                onFill: _fill,
              ),
              _VerdictCard(state: state),
            ],
          ),
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.domain,
    required this.qtype,
    required this.running,
    required this.onQtype,
    required this.onRun,
    required this.onFill,
  });

  final TextEditingController domain;
  final String qtype;
  final bool running;
  final ValueChanged<String> onQtype;
  final VoidCallback onRun;
  final ValueChanged<String> onFill;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopToolsRuleInputTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.search,
            title: l10n.desktopToolsRuleInputTitle,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopToolsRuleInputBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: domain,
            style: AppTextStyle.callout.of(context).toTabular,
            decoration: InputDecoration(
              labelText: l10n.desktopToolsRuleDomain,
              hintText: l10n.desktopToolsRuleDomainHint,
            ),
            onSubmitted: (_) => onRun(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.desktopToolsRuleQtype,
                style: DashboardText.rowTitle(context),
              ),
              DesktopPicker(
                glyph: AppGlyphs.layers,
                semanticLabel: l10n.desktopToolsRuleQtype,
                label: qtype,
                active: true,
                items: [
                  for (final type in _qtypes)
                    CommonPopupMenuItem(
                      label: l10n.desktopToolsRuleQtypeOption(type),
                      checked: type == qtype,
                      onPressed: () => onQtype(type),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.desktopToolsRuleExamples,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final example in _examples)
                CommonCard(
                  onPressed: running ? null : () => onFill(example),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    example,
                    style: AppTextStyle.caption1
                        .of(context, emphasized: true)
                        .toTabular,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: running ? null : onRun,
            child: Text(
              running ? l10n.desktopToolsRuleRunning : l10n.desktopToolsRuleRun,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.state});

  final DesktopRuleCheckState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = state.result;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopToolsRuleVerdictTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.verified,
            title: l10n.desktopToolsRuleVerdictTitle,
            leading: [
              if (result != null)
                DashboardChip(
                  label: _verdictLabel(context, result),
                  tone: result.blocked
                      ? DashboardChipTone.warn
                      : result.isAllow || result.isRewrite
                      ? DashboardChipTone.ok
                      : DashboardChipTone.idle,
                  dot: true,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopToolsRuleVerdictBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          if (state.error case final error?)
            Text(
              l10n.desktopToolsRuleFailed(error.message),
              style: DashboardText.label(context, color: colorScheme.error),
            )
          else if (result == null)
            Text(l10n.desktopToolsRuleIdle, style: DashboardText.label(context))
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  state.domain,
                  style: DashboardText.rowTitle(context).toTabular,
                ),
                DashboardChip(label: state.qtype, tone: DashboardChipTone.idle),
              ],
            ),
            const SizedBox(height: 10),
            _Field(
              label: l10n.desktopToolsRuleMatched,
              value: result.matchedRule.isEmpty
                  ? l10n.desktopToolsRuleNoMatch
                  : result.matchedRule,
              mono: true,
            ),
            _Field(
              label: l10n.desktopToolsRuleList,
              value: result.listName.isEmpty
                  ? l10n.desktopToolsRuleNoList
                  : result.listName,
            ),
            _Field(
              label: l10n.desktopToolsRuleReason,
              value: result.reason.isEmpty
                  ? l10n.desktopToolsRuleNoReason
                  : result.reason,
            ),
            if (result.isRewrite) ...[
              const SizedBox(height: 6),
              Text(
                l10n.desktopToolsRuleRewrite(
                  desktopRcodeName(result.rewritten!.rcode),
                ),
                style: DashboardText.label(context),
              ),
              if (result.rewritten!.summary.isEmpty)
                Text(
                  l10n.desktopToolsRuleRewriteEmpty,
                  style: DashboardText.label(context),
                )
              else
                for (final record in result.rewritten!.summary)
                  Text(record, style: DashboardText.label(context).toTabular),
            ],
          ],
          const SizedBox(height: 6),
          Text(
            l10n.desktopToolsRuleFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

String _verdictLabel(BuildContext context, DesktopRuleCheckResult result) {
  final l10n = context.l10n;
  if (result.blocked) return l10n.desktopToolsRuleBlocked;
  if (result.isRewrite) {
    return l10n.desktopToolsRuleRewritten(
      desktopRcodeName(result.rewritten!.rcode),
    );
  }
  if (result.isAllow) return l10n.desktopToolsRuleAllowed;
  return l10n.desktopToolsRulePassed;
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final style = DashboardText.label(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(label, style: style),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: mono ? style.toTabular : style,
          ),
        ],
      ),
    );
  }
}
