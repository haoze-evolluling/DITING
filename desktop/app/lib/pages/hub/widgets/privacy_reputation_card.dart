/// The reputation lookups: malicious-site checking, its switch and the counters behind it.
///
/// The old desktop console's `SafeBrowsingCard.vue` is the blueprint. The switch saves one field;
/// the timeout and cache numbers beside it are [PrivacyReputationParamsCard], and parental control is
/// [PrivacyParentalCard], so this card stays a reading of what the lookup is doing.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';
import 'package:diting_desktop/data/api/desktop_reputation_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/pages/hub/widgets/privacy_common.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacyReputationCard extends ConsumerWidget {
  const PrivacyReputationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopReputationProvider);
    final data = state.data;
    final saving = state.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopReputationTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.gavel,
            title: l10n.desktopReputationTitle,
            leading: [
              if (data != null)
                DashboardChip(
                  label: data.enabled
                      ? l10n.desktopReputationOn
                      : l10n.desktopReputationOff,
                  tone: data.enabled
                      ? DashboardChipTone.ok
                      : DashboardChipTone.idle,
                  dot: data.enabled,
                ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else if (data != null)
                DashboardSwitch(
                  value: data.enabled,
                  semanticLabel: l10n.desktopReputationTitle,
                  onChanged: (value) => unawaited(
                    savePrivacySetting(
                      context,
                      ref,
                      () => ref
                          .read(desktopReputationProvider.notifier)
                          .save({'enabled': value}),
                      value
                          ? l10n.desktopReputationOnMessage
                          : l10n.desktopReputationOffMessage,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopReputationBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (data == null)
            _Unavailable(
              loading: state.isLoading,
              onRetry: ref.read(desktopReputationProvider.notifier).reload,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final metrics = [
                  FilterMetric(
                    label: l10n.desktopReputationLookups,
                    value: dashboardCount(data.lookups),
                  ),
                  FilterMetric(
                    label: l10n.desktopReputationBlocked,
                    value: dashboardCount(data.blocked),
                  ),
                  FilterMetric(
                    label: l10n.desktopReputationHitRate,
                    value: data.hitRate == null
                        ? '—'
                        : '${(data.hitRate! * 100).round()}',
                    unit: data.hitRate == null ? null : '%',
                  ),
                  FilterMetric(
                    label: l10n.desktopReputationFailures,
                    value: dashboardCount(data.failures),
                  ),
                  FilterMetric(
                    label: l10n.desktopReputationAnswer,
                    value: desktopReputationAnswer(context, data),
                  ),
                ];
                if (constraints.maxWidth < 620) {
                  return Wrap(spacing: 20, runSpacing: 10, children: metrics);
                }
                return Row(
                  spacing: 14,
                  children: [
                    for (final metric in metrics) Expanded(child: metric),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

String desktopReputationAnswer(BuildContext context, DesktopSafeBrowsing data) {
  final l10n = context.l10n;
  return switch (data.blockMode) {
    'nxdomain' => 'NXDOMAIN',
    'refused' => 'REFUSED',
    _ => data.blockingIpv4.isEmpty
        ? l10n.desktopReputationAnswerNullIp
        : data.blockingIpv4,
  };
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.loading, required this.onRetry});

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CommonCircleLoading(size: 20)),
      );
    }
    return FilledButton.tonal(
      onPressed: onRetry,
      child: Text(l10n.desktopRetry),
    );
  }
}
