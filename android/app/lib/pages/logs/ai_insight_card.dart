import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/agent/agent_analysis_target.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/pages/hub/agent_analysis_sheet.dart';
import 'package:diting_android/state/agent_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class AiInsightCard extends ConsumerWidget {
  const AiInsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentAnalysisProvider);
    final colorScheme = context.colorScheme;
    final scale = DashboardDensityScope.scaleOf(context);
    final report = state.success && state.target is AgentTrafficTarget
        ? state.content
        : null;
    final hasReport = report != null;
    final headline = report == null ? null : _headlineOf(report);

    return DashboardCard(
      semanticLabel: context.l10n.logsAiInsight,
      onTap: () => _open(context, state.sessionId, hasReport),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.sparkle,
            title: context.l10n.logsAiInsight,
            trailing: [
              DashboardChip(
                label: hasReport
                    ? context.l10n.logsHasReport
                    : context.l10n.logsNotAnalysed,
                tone: hasReport ? DashboardChipTone.ok : DashboardChipTone.idle,
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          if (headline == null)
            Text(
              context.l10n.logsAiInsightBody,
              style: AppTextRole.bodyReading
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            )
          else ...[
            Text(
              headline,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextRole.bodyReading.of(context),
            ),
            SizedBox(height: 6 * scale),
            Text(
              [
                if (state.model case final model? when model.isNotEmpty)
                  context.l10n.logsModelName(model),
                if (state.startedAt case final at?)
                  '${at.hour.toString().padLeft(2, '0')}:'
                      '${at.minute.toString().padLeft(2, '0')}',
              ].join(' · '),
              style: DashboardText.label(context),
            ),
          ],
          SizedBox(height: 12 * scale),
          Align(
            alignment: Alignment.centerLeft,
            child: TonalButton(
              size: TonalButtonSize.compact,
              glyph: hasReport ? AppGlyphs.chevronForward : AppGlyphs.sparkle,
              label: hasReport
                  ? context.l10n.logsViewFullReport
                  : context.l10n.logsAnalyseTraffic,
              onPressed: () => _open(context, state.sessionId, hasReport),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, int sessionId, bool adopt) {
    showSheet<void>(
      context: context,
      builder: (_) => AgentAnalysisSheet(
        target: const AgentTrafficTarget(),
        adoptSessionId: adopt ? sessionId : 0,
      ),
    );
  }
}

String? _headlineOf(String markdown) {
  for (final line in markdown.split('\n')) {
    final text = line
        .trim()
        .replaceAll(RegExp(r'^#{1,6}\s*'), '')
        .replaceAll(RegExp(r'^(?:[-*+]|\d+\.)\s*'), '')
        .replaceAll(RegExp(r'^(?:-{3,}|\*{3,}|_{3,})$'), '')
        .replaceAll(RegExp(r'[*_~`]'), '')
        .trim();
    if (text.length < 8) continue;
    if (RegExp(r'^【?(?:近期|总体|摘要|结论|分析)').hasMatch(text)) continue;
    return text;
  }
  return null;
}
