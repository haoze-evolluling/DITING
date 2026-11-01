/// The rewrite rule table: a client-side search over the fields the console searches, one row per
/// rule, and the two row actions.
///
/// The console filters the list it already has (`RewritePanel.vue`); there is no server-side search
/// endpoint for rewrite rules, so this page does the same instead of inventing one.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_rewrite_models.dart';
import 'package:diting/desktop/data/api/desktop_rewrite_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/rewrite_common.dart';
import 'package:diting/desktop/pages/hub/widgets/rewrite_editor_dialog.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _typeWidth = 168;
const double _ttlWidth = 80;
const double _actionsWidth = 84;

/// Below this the TTL column is dropped; the name, the chips, the target and the actions still fit.
const double _wideBreakpoint = 900;

class RewriteRulesCard extends ConsumerStatefulWidget {
  const RewriteRulesCard({
    super.key,
    required this.config,
    required this.saving,
  });

  final DesktopRewriteConfig config;
  final bool saving;

  @override
  ConsumerState<RewriteRulesCard> createState() => _RewriteRulesCardState();
}

class _RewriteRulesCardState extends ConsumerState<RewriteRulesCard> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final rule = await showRewriteEditor(context);
    if (rule == null || !mounted) return;
    await _save(rule);
  }

  Future<void> _edit(DesktopRewriteRule rule) async {
    final next = await showRewriteEditor(context, editing: rule);
    if (next == null || !mounted) return;
    await _save(next);
  }

  Future<void> _save(DesktopRewriteRule rule) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopRewriteProvider.notifier)
        .saveRule(rule);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopRewriteRuleSaved(rule.domain)
          : l10n.desktopRewriteRuleFailed(error.message),
    );
  }

  Future<void> _delete(DesktopRewriteRule rule) async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopRewriteDeleteTitle,
      body: l10n.desktopRewriteDeleteBody(rule.domain),
      confirmLabel: l10n.desktopRewriteDelete,
    );
    if (!confirmed || !mounted) return;
    final error = await ref
        .read(desktopRewriteProvider.notifier)
        .deleteRule(rule.domain);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopRewriteRuleDeleted(rule.domain)
          : l10n.desktopRewriteDeleteFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rules = [
      for (final rule in widget.config.rules)
        if (rule.matches(_query.toLowerCase())) rule,
    ];
    return DashboardCard(
      semanticLabel: l10n.desktopRewriteRulesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: l10n.desktopRewriteRulesTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopRewriteRulesCount(
                  widget.config.rules.length,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopRewriteRulesBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: SearchField(
                  controller: _search,
                  hintText: l10n.desktopRewriteSearch,
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              if (_query.isNotEmpty)
                TextButton(
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  child: Text(l10n.desktopRewriteResetSearch),
                ),
              TonalButton(
                size: TonalButtonSize.compact,
                glyph: AppGlyphs.add,
                label: l10n.desktopRewriteAdd,
                onPressed: widget.saving ? null : () => unawaited(_add()),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) => _table(
              context,
              rules,
              wide: constraints.maxWidth >= _wideBreakpoint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(
    BuildContext context,
    List<DesktopRewriteRule> rules, {
    required bool wide,
  }) {
    final l10n = context.l10n;
    if (rules.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          widget.config.rules.isEmpty
              ? l10n.desktopRewriteEmpty
              : l10n.desktopRewriteNoMatch,
          textAlign: TextAlign.center,
          style: DashboardText.label(context),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(wide: wide),
        for (final (index, rule) in rules.indexed) ...[
          if (index > 0 || wide) const _Divider(),
          _Row(
            rule: rule,
            config: widget.config,
            wide: wide,
            saving: widget.saving,
            onEdit: () => unawaited(_edit(rule)),
            onDelete: () => unawaited(_delete(rule)),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = DashboardText.label(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            flex: 3,
            child: Text(l10n.desktopRewriteDomain, style: style),
          ),
          SizedBox(
            width: _typeWidth,
            child: Text(l10n.desktopRewriteTypes, style: style),
          ),
          Expanded(
            flex: 5,
            child: Text(l10n.desktopRewriteTarget, style: style),
          ),
          if (wide)
            SizedBox(
              width: _ttlWidth,
              child: Text(
                l10n.desktopRewriteTtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: style,
              ),
            ),
          SizedBox(
            width: _actionsWidth,
            child: Text(
              l10n.desktopRewriteActions,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rule,
    required this.config,
    required this.wide,
    required this.saving,
    required this.onEdit,
    required this.onDelete,
  });

  final DesktopRewriteRule rule;
  final DesktopRewriteConfig config;
  final bool wide;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              rule.domain,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.rowTitle(context),
            ),
          ),
          SizedBox(
            width: _typeWidth,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (rule.typeLabels.isEmpty)
                  DashboardChip(label: l10n.desktopRewriteChipEmpty)
                else
                  for (final type in rule.typeLabels)
                    DashboardChip(
                      label: desktopRewriteTypeLabel(context, type),
                      tone: desktopRewriteTypeTone(type),
                    ),
              ],
            ),
          ),
          Expanded(flex: 5, child: _Target(rule: rule)),
          if (wide)
            SizedBox(
              width: _ttlWidth,
              child: Text(
                l10n.desktopRewriteSeconds(desktopRewriteRuleTtl(rule, config)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: DashboardText.label(context),
              ),
            ),
          SizedBox(
            width: _actionsWidth,
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 4,
              children: [
                DashboardIconButton(
                  glyph: AppGlyphs.edit,
                  tooltip: l10n.desktopRewriteEdit,
                  onPressed: saving ? null : onEdit,
                ),
                DashboardIconButton(
                  glyph: AppGlyphs.delete,
                  tooltip: l10n.desktopRewriteDelete,
                  onPressed: saving ? null : onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the rule answers: the failure code, the alias, the addresses, the text lines or the explicit
/// records. One line each, with the remainder counted, so a long rule cannot push the table apart.
class _Target extends StatelessWidget {
  const _Target({required this.rule});

  final DesktopRewriteRule rule;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final label = DashboardText.label(context);
    if (rule.isRcodeFailure) {
      return Text(
        l10n.desktopRewriteRcodeOnly(rule.rcode),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: label.copyWith(color: colorScheme.warning),
      );
    }
    if (!rule.hasTarget) {
      return Text(
        l10n.desktopRewriteNoTarget,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: label,
      );
    }
    final parts = <String>[
      if (rule.cname.isNotEmpty) rule.cname,
      if (rule.ips.isNotEmpty) rule.ips.join(' · '),
      if (rule.txt.isNotEmpty)
        '"${rule.txt.first}"${rule.txt.length > 1 ? ' +${rule.txt.length - 1}' : ''}',
      for (final record in rule.records) '${record.type} ${record.value}',
    ];
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: label,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    color: context.colorScheme.onSurface.withValues(alpha: 0.06),
  );
}
