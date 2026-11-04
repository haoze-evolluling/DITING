/// Building blocks shared by the request detail and DNS cache detail sheets, so the two sheets
/// keep one look and one set of domain actions.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/agent/agent_analysis_target.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/rules/rule_domain_utils.dart';
import 'package:diting_android/pages/hub/agent_analysis_sheet.dart';
import 'package:diting_android/pages/observability/observability_common.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_android/state/rules_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Summary card: status badge, selectable host, one-line explanation and classifying chips.
class DetailHeroCard extends StatelessWidget {
  const DetailHeroCard({
    super.key,
    required this.glyph,
    required this.color,
    required this.title,
    required this.subtitle,
    this.chips = const [],
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String subtitle;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CommonCard(
        inert: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                IconBadge(
                  glyph: glyph,
                  color: color.withValues(alpha: 0.14),
                  foregroundColor: color,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      SelectableText(
                        title,
                        style: AppTextStyle.headline
                            .of(context)
                            .copyWith(
                              color: colorScheme.onSurface,
                              fontFeatures: appTabularFigures,
                            ),
                      ),
                      Text(subtitle, style: context.listCaptionStyle),
                    ],
                  ),
                ),
              ],
            ),
            if (chips.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
        ),
      ),
    );
  }
}

/// Neutral chip for the hero card; a status chip passes its own colors to [TonalChip].
class DetailMetaChip extends StatelessWidget {
  const DetailMetaChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return TonalChip(
      label: label,
      color: context.raisedSurfaceLevel.colorOf(colorScheme),
      foregroundColor: colorScheme.onSurfaceVariant,
    );
  }
}

/// Copy, blacklist and whitelist buttons for [host]. Domain rules match query names, so a literal
/// IP can only be copied, and a note under the row says why the rule buttons are off.
class DomainActionRow extends ConsumerWidget {
  const DomainActionRow({super.key, required this.host});

  /// Bare host without port or trailing dot; null when the record has none.
  final String? host;

  Future<void> _copy(BuildContext context, String host) async {
    await Clipboard.setData(ClipboardData(text: host));
    if (!context.mounted) return;
    showObsTip(context, context.l10n.obsCopiedHost(host));
  }

  Future<void> _addRule(
    BuildContext context,
    WidgetRef ref,
    RuleKind kind,
    String domain,
  ) async {
    final added = await ref.read(rulesProvider.notifier).add(kind, domain);
    if (!context.mounted) return;
    showObsTip(
      context,
      added
          ? context.l10n.obsAddedToKind(
              domain,
              kind.title(context.l10n),
            )
          : context.l10n.obsAlreadyInKind(
              domain,
              kind.title(context.l10n),
            ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final host = this.host;
    final domain = host == null ? null : normalizeDomain(host);
    bool listed(RuleKind kind) =>
        domain != null &&
        ref
            .watch(rulesOfKindProvider(kind))
            .any((rule) => rule.pattern == domain);
    final inBlock = listed(RuleKind.block);
    final inAllow = listed(RuleKind.allow);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: _QuickAction(
                  glyph: AppGlyphs.copy,
                  label: host != null && domain == null ? context.l10n.obsCopyAddress : context.l10n.obsCopyDomain,
                  color: colorScheme.primary,
                  onPressed: host == null ? null : () => _copy(context, host),
                ),
              ),
              Expanded(
                child: _QuickAction(
                  glyph: AppGlyphs.block,
                  label: inBlock ? context.l10n.obsInBlocklist : context.l10n.obsAddToBlocklist,
                  color: colorScheme.error,
                  onPressed: domain == null || inBlock
                      ? null
                      : () => _addRule(context, ref, RuleKind.block, domain),
                ),
              ),
              Expanded(
                child: _QuickAction(
                  glyph: AppGlyphs.checkCircle,
                  label: inAllow ? context.l10n.obsInAllowlist : context.l10n.obsAddToAllowlist,
                  color: colorScheme.success,
                  onPressed: domain == null || inAllow
                      ? null
                      : () => _addRule(context, ref, RuleKind.allow, domain),
                ),
              ),
            ],
          ),
        ),
        if (host != null && domain == null)
          ListFooter(text: context.l10n.obsIpOnlyFooter),
      ],
    );
  }
}

/// Icon over label in a card; disabled when [onPressed] is null.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.glyph,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final Glyph glyph;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final tint = enabled ? color : context.colorScheme.onSurfaceVariant;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: CommonCard(
        onPressed: onPressed,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            IconBadge(
              glyph: glyph,
              size: 40,
              glyphSize: 20,
              color: tint.withValues(alpha: 0.14),
              foregroundColor: tint,
              shape: AppShape.circle,
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline
                  .of(context, emphasized: true)
                  .copyWith(color: context.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rows of `KeyValueRow` on one card, the layout the traffic detail sheet uses.
class DetailInfoCard extends StatelessWidget {
  const DetailInfoCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      inert: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// "AI analysis" section for detail sheets; renders nothing until an API key is configured.
class AgentAnalysisSection extends ConsumerWidget {
  const AgentAnalysisSection({super.key, required this.domain, this.title});

  final String domain;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(agentKeyConfiguredProvider)) return const SizedBox.shrink();
    return SectionBlock(
      title: context.l10n.obsAiAnalysis,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: AgentAnalysisEntryCard(domain: domain, title: title),
    );
  }
}

/// Tappable card that opens the AI report for [domain] above the current sheet.
class AgentAnalysisEntryCard extends StatelessWidget {
  const AgentAnalysisEntryCard({
    super.key,
    required this.domain,
    this.title,
  });

  final String domain;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onPressed: () => openAgentAnalysis(context, AgentDomainTarget(domain)),
      child: Row(
        spacing: 12,
        children: [
          IconBadge(
            glyph: AppGlyphs.sparkle,
            size: 38,
            glyphSize: 20,
            color: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            shape: AppShape.circle,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title ?? context.l10n.obsAnalyzeRequest,
                  style: context.listTitleStyle,
                ),
                Text(context.l10n.obsAnalyzeRequestBody, style: context.listCaptionStyle),
              ],
            ),
          ),
          GlyphIcon(
            AppGlyphs.chevronForward,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
