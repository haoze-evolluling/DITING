/// U1 保护健康页：从「是否运行」升级到「是否有效」，给出四维评分与下一步建议。
library;

import 'package:diting_android/pages/health/health_score.dart';
import 'package:diting_android/state/health_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class HealthPage extends ConsumerWidget {
  const HealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReport = ref.watch(healthReportProvider);
    return CommonScaffold(
      title: context.l10n.healthTitle,
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.healthIntro),
          asyncReport.when(
            loading: () => _paddedCard(context, Text(context.l10n.healthLoading)),
            error: (error, _) =>
                _paddedCard(context, Text(context.l10n.healthLoadFailed)),
            data: (report) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                _ScoreCard(report: report),
                generateSection(
                  title: context.l10n.healthDimensionsTitle,
                  items: [
                    for (final dimension in report.dimensions)
                      _DimensionRow(dimension: dimension),
                  ],
                ),
                generateSection(
                  title: context.l10n.healthAdviceTitle,
                  items: [
                    for (final advice in report.advices)
                      _AdviceRow(advice: advice),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _severityColor(BuildContext context, HealthSeverity severity) {
  final scheme = context.colorScheme;
  return switch (severity) {
    HealthSeverity.ok => scheme.success,
    HealthSeverity.warning => scheme.warning,
    HealthSeverity.critical => scheme.error,
  };
}

String _levelLabel(AppL10n l10n, HealthSeverity level) => switch (level) {
  HealthSeverity.ok => l10n.healthLevelOk,
  HealthSeverity.warning => l10n.healthLevelWarning,
  HealthSeverity.critical => l10n.healthLevelCritical,
};

String _dimensionLabel(AppL10n l10n, HealthDimensionKind kind) => switch (kind) {
  HealthDimensionKind.permissions => l10n.healthDimPermissions,
  HealthDimensionKind.dns => l10n.healthDimDns,
  HealthDimensionKind.filter => l10n.healthDimFilter,
  HealthDimensionKind.cache => l10n.healthDimCache,
};

String _adviceText(AppL10n l10n, String id) => switch (id) {
  'grantPermissions' => l10n.healthAdviceGrantPermissions,
  'startProtection' => l10n.healthAdviceStartProtection,
  'importRules' => l10n.healthAdviceImportRules,
  'updateSubscriptions' => l10n.healthAdviceUpdateSubscriptions,
  'lowCache' => l10n.healthAdviceLowCache,
  'noBlocking' => l10n.healthAdviceNoBlocking,
  _ => l10n.healthAdviceAllGood,
};

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final HealthReport report;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(context, report.level);
    return _paddedCard(
      context,
      Row(
        spacing: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${report.score}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                context.l10n.healthScoreLabel,
                style: context.listCaptionStyle,
              ),
            ],
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  _levelLabel(context.l10n, report.level),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                  ),
                ),
                Text(
                  context.l10n.healthIntroShort,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DimensionRow extends StatelessWidget {
  const _DimensionRow({required this.dimension});

  final HealthDimension dimension;

  @override
  Widget build(BuildContext context) {
    final severity = dimension.score >= 80
        ? HealthSeverity.ok
        : (dimension.score >= 55
              ? HealthSeverity.warning
              : HealthSeverity.critical);
    final color = _severityColor(context, severity);
    return ListItem(
      leading: GlyphIcon(AppGlyphs.checkCircle, color: color),
      title: Text(_dimensionLabel(context.l10n, dimension.kind)),
      trailing: Text(
        '${dimension.score}',
        style: AppTextStyle.subheadline
            .of(context, emphasized: true)
            .toTabular
            .copyWith(color: color),
      ),
    );
  }
}

class _AdviceRow extends StatelessWidget {
  const _AdviceRow({required this.advice});

  final HealthAdvice advice;

  @override
  Widget build(BuildContext context) {
    final icon = switch (advice.severity) {
      HealthSeverity.ok => AppGlyphs.checkCircle,
      HealthSeverity.warning => AppGlyphs.warning,
      HealthSeverity.critical => AppGlyphs.error,
    };
    return ListItem(
      leading: GlyphIcon(icon, color: _severityColor(context, advice.severity)),
      title: Text(_adviceText(context.l10n, advice.id)),
    );
  }
}

Widget _paddedCard(BuildContext context, Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: CommonCard(padding: const EdgeInsets.all(16), child: child),
);
