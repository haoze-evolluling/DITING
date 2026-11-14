/// R2 命中排行：被拦截最多的域名和命中原因，点域名可跳规则测试解释判定。
library;

import 'package:diting_android/pages/logs/logs_overview_card.dart';
import 'package:diting_android/pages/logs/logs_shared.dart';
import 'package:diting_android/state/hit_ranking_providers.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class HitRankingPage extends ConsumerWidget {
  const HitRankingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSnapshot = ref.watch(hitRankingProvider);
    final range = ref.watch(hitRankingRangeProvider);
    return CommonScaffold(
      title: context.l10n.hitRankingTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.logsRefresh,
          onPressed: () => ref.read(dnsLogRevisionProvider.notifier).bump(),
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: SliverPageBody(
        slivers: [
          SliverToBoxAdapter(
            child: generateSection(
              title: context.l10n.logsTimeRange,
              items: [
                LogStatsRangeSelector<LogStatsRange>(
                  values: LogStatsRange.values,
                  labelOf: (option) => option.label(context.l10n),
                  value: range,
                  onChanged: (value) =>
                      ref.read(hitRankingRangeProvider.notifier).select(value),
                ),
              ],
            ),
          ),
          ..._sections(context, asyncSnapshot),
          SliverToBoxAdapter(
            child: ListFooter(text: context.l10n.hitRankingFooter),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(
    BuildContext context,
    AsyncValue<HitRankingSnapshot> asyncSnapshot,
  ) {
    if (!asyncSnapshot.hasValue) {
      if (asyncSnapshot.hasError) {
        return [
          SliverToBoxAdapter(
            child: generateSection(
              title: context.l10n.hitRankingTitle,
              items: [
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.error),
                  title: Text(context.l10n.hitRankingLoadFailed),
                  subtitle: Text('${asyncSnapshot.error}'),
                ),
              ],
            ),
          ),
        ];
      }
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text(context.l10n.logsLoadingStats)),
          ),
        ),
      ];
    }

    final snapshot = asyncSnapshot.requireValue;
    final l10n = context.l10n;
    if (snapshot.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: generateSection(
            title: l10n.hitRankingTitle,
            items: [
              LogsSectionEmpty(
                glyph: AppGlyphs.block,
                title: l10n.hitRankingEmpty,
                description: l10n.hitRankingEmptyBody,
              ),
            ],
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: generateSection(
          title: l10n.hitRankingDomains,
          footer: l10n.hitRankingDomainsFooter,
          items: [
            for (final row in snapshot.domains)
              ListItem(
                leading: const GlyphIcon(AppGlyphs.block),
                title: Text(row.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(l10n.hitRankingExplainHint),
                trailing: Text(
                  countOf(row.count),
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .toTabular,
                ),
                // 一键解释：把域名预填进规则测试，按当前规则复现判定。
                onTap: () => context.push(
                  '/hub/rules/test?domain=${Uri.encodeComponent(row.label)}',
                ),
              ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: generateSection(
          title: l10n.hitRankingReasons,
          items: [
            for (final row in snapshot.reasons)
              ListItem(
                leading: const GlyphIcon(AppGlyphs.rules),
                title: Text(row.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(
                  countOf(row.count),
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .toTabular,
                ),
              ),
          ],
        ),
      ),
    ];
  }
}
