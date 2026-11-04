/// IP quality (upstream `features/ip_quality/ip_quality_sheet.dart`).
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/tools/ip_quality_checker.dart';
import 'package:diting_android/state/system_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/note_card.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:diting_android/widgets/status_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The four IP type badge values (upstream `IpType`).
enum IpType {
  residential(AppGlyphs.account),
  mobile(AppGlyphs.devices),
  business(AppGlyphs.profiles),
  hosting(AppGlyphs.cpu);

  const IpType(this.glyph);

  final Glyph glyph;

  String label(AppL10n l10n) => switch (this) {
    residential => l10n.ipTypeResidential,
    mobile => l10n.ipTypeMobile,
    business => l10n.ipTypeBusiness,
    hosting => l10n.ipTypeHosting,
  };
}

/// IP quality level (upstream `IpQualityLevel`, with matching three-tier colors).
enum IpQualityLevel {
  good,
  normal,
  risky;

  String label(AppL10n l10n) => switch (this) {
    good => l10n.ipLevelGood,
    normal => l10n.ipLevelNormal,
    risky => l10n.ipLevelRisky,
  };
}

/// Result of one source (upstream `IpQualitySourceStatus`).
enum IpQualitySourceStatus {
  ok,
  noType,
  timeout,
  rateLimited,
  failed,
  ipMismatch;

  String label(AppL10n l10n) => switch (this) {
    ok => l10n.ipStatusOk,
    noType => l10n.ipStatusNoType,
    timeout => l10n.ipStatusTimeout,
    rateLimited => l10n.ipStatusRateLimited,
    failed => l10n.commonFailed,
    ipMismatch => l10n.ipStatusMismatch,
  };

  bool get isError => this != ok;
}

/// Parses a string enum; unknown values become failures instead of crashing.
IpQualitySourceStatus _statusOf(String raw) => switch (raw) {
  '命中' => IpQualitySourceStatus.ok,
  '无类型' => IpQualitySourceStatus.noType,
  '超时' => IpQualitySourceStatus.timeout,
  '限流' => IpQualitySourceStatus.rateLimited,
  'IP 不一致' => IpQualitySourceStatus.ipMismatch,
  _ => IpQualitySourceStatus.failed,
};

IpType _typeOf(String raw) => switch (raw) {
  '住宅' => IpType.residential,
  '移动' => IpType.mobile,
  '商业' => IpType.business,
  _ => IpType.hosting,
};

IpQualityLevel _levelOf(String raw) => switch (raw) {
  '优秀' => IpQualityLevel.good,
  '一般' => IpQualityLevel.normal,
  _ => IpQualityLevel.risky,
};

class IpQualityPage extends ConsumerStatefulWidget {
  const IpQualityPage({super.key});

  @override
  ConsumerState<IpQualityPage> createState() => _IpQualityPageState();
}

class _IpQualityPageState extends ConsumerState<IpQualityPage> {
  @override
  void initState() {
    super.initState();
    // Re-probe on entry: the egress IP may have changed since the last run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(ipQualityProvider.notifier).detect();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ipQualityProvider);
    return CommonScaffold(
      title: context.l10n.devIpQuality,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: context.l10n.ipQualityRedetect,
          isLoading: state.stage == IpQualityStage.loading,
          onPressed: () => ref.read(ipQualityProvider.notifier).detect(),
        ),
      ],
      body: PageBody(
        children: [
          IpQualitySheet(
            report: state.report,
            stage: state.stage,
            error: state.error,
            onRetry: () => ref.read(ipQualityProvider.notifier).detect(),
          ),
        ],
      ),
    );
  }
}

/// `StatelessWidget` so both the page and `showIpQualitySheet` can use it.
class IpQualitySheet extends StatelessWidget {
  const IpQualitySheet({
    super.key,
    required this.report,
    required this.stage,
    this.error,
    this.onRetry,
  });

  /// The real probe result; `null` means no successful probe yet.
  final IpQualityReport? report;
  final IpQualityStage stage;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    if (report == null) {
      // Without a report, speak per stage: spinner, reason and retry, or a hint. No
      // hard-coded sample is shown.
      return _EmptyReport(stage: stage, error: error, onRetry: onRetry);
    }
    final current = report!;
    final type = _typeOf(current.ipType);
    final level = _levelOf(current.level);
    final levelColor = switch (level) {
      IpQualityLevel.good => colorScheme.success,
      IpQualityLevel.normal => colorScheme.onSurfaceVariant,
      IpQualityLevel.risky => colorScheme.error,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: CommonCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          Text(context.l10n.ipQualityEgress, style: context.listCaptionStyle),
                          Text(
                            current.ip,
                            style: AppTextStyle.title2
                                .of(context, emphasized: true)
                                .copyWith(fontFeatures: appTabularFigures),
                          ),
                        ],
                      ),
                    ),
                    if (stage == IpQualityStage.loading)
                      const CommonCircleLoading()
                    else
                      StatusPill(
                        label: level.label(context.l10n),
                        color: levelColor,
                        alpha: 0.14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        style: AppTextStyle.subheadline,
                      ),
                  ],
                ),
                Row(
                  spacing: 8,
                  children: [
                    _TypeBadge(type: type),
                    // The ASN is capped and may ellipsize, otherwise a long org name
                    // overflows the card (`RIGHT OVERFLOWED BY 51 PIXELS`).
                    if (current.asn.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: MetaChip(label: current.asn),
                      ),
                    // The org name must be `Expanded`: `Spacer` only distributes leftover
                    // space, so an unconstrained `Text` overflows the `Row`.
                    Expanded(
                      child: Text(
                        current.organization,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.listCaptionStyle,
                      ),
                    ),
                  ],
                ),
                if (stage == IpQualityStage.loading) const ProgressLine(),
              ],
            ),
          ),
        ),
        generateSection(
          title: context.l10n.ipQualitySources,
          items: [
            for (final source in current.sources) _SourceRow(source: source),
          ],
          footer:
              context.l10n.ipQualitySourcesFooter,
        ),
        if (stage == IpQualityStage.loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(context.l10n.ipQualityQuerying, style: context.listCaptionStyle),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TonalButton(
            label: stage == IpQualityStage.loading ? context.l10n.ipQualityChecking : context.l10n.ipQualityRedetect,
            glyph: AppGlyphs.refresh,
            size: TonalButtonSize.section,
            onPressed: stage == IpQualityStage.loading ? null : onRetry,
          ),
        ),
      ],
    );
  }
}

/// Placeholder before any report exists; no constant sample is rendered.
class _EmptyReport extends StatelessWidget {
  const _EmptyReport({required this.stage, this.error, this.onRetry});

  final IpQualityStage stage;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final loading = stage == IpQualityStage.loading;
    final failed = stage == IpQualityStage.failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: CommonCard(
            padding: const EdgeInsets.all(16),
            isError: failed,
            child: Row(
              spacing: 12,
              children: [
                if (loading)
                  const CommonCircleLoading()
                else
                  GlyphIcon(
                    failed ? AppGlyphs.error : AppGlyphs.cloudSync,
                    size: 22,
                    color: failed
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        loading ? context.l10n.ipQualityDetecting : (failed ? context.l10n.ipQualityFailed : context.l10n.ipQualityNotYet),
                        style: context.listTitleStyle,
                      ),
                      Text(
                        error ??
                            (loading
                                ? context.l10n.ipQualityDetectingBody
                                : context.l10n.ipQualityStartBody),
                        style: context.listCaptionStyle.copyWith(
                          color: failed ? colorScheme.error : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TonalButton(
            label: loading ? context.l10n.ipQualityChecking : context.l10n.ipQualityStart,
            glyph: AppGlyphs.refresh,
            size: TonalButtonSize.section,
            onPressed: loading ? null : onRetry,
          ),
        ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final IpType type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return StatusPill(
      label: type.label(context.l10n),
      color: colorScheme.secondaryContainer,
      foregroundColor: colorScheme.onSecondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      emphasized: false,
      leading: type.glyph,
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});

  final IpSourceResult source;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final status = _statusOf(source.status);
    final color = status.isError ? colorScheme.error : colorScheme.success;
    final ipType = source.ipType;
    final latency = source.latencyMs;
    final detail = source.detail;
    return ListItem(
      leading: GlyphIcon(
        status.isError ? AppGlyphs.warning : AppGlyphs.checkCircle,
        color: color,
      ),
      title: Text(source.name),
      // `Wrap` rather than `Row`: four text segments overflow a `Row` on narrow screens
      // with large text.
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 2,
        children: [
          Text(
            status.label(context.l10n),
            style: context.listCaptionStyle.copyWith(color: color),
          ),
          if (ipType != null)
            Text(
              context.l10n.ipQualityJudgedAs(
                _typeOf(ipType).label(context.l10n),
              ),
              style: context.listCaptionStyle,
            ),
          if (latency != null)
            Text(
              '${latency}ms',
              style: context.listCaptionStyle.copyWith(
                fontFeatures: appTabularFigures,
              ),
            ),
          // The reason is shown: "failed" alone cannot tell rate limiting apart.
          if (detail != null && detail.isNotEmpty)
            Text(detail, style: context.listCaptionStyle),
        ],
      ),
      trailing: status.isError
          ? TonalChip(
              label: context.l10n.ipQualityNotUsed,
              color: colorScheme.errorContainer,
              foregroundColor: colorScheme.onErrorContainer,
            )
          : TonalChip(
              label: context.l10n.ipQualityUsed,
              color: colorScheme.successContainer,
              foregroundColor: colorScheme.onSuccessContainer,
            ),
    );
  }
}
