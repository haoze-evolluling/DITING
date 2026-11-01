/// The ten names with the most local cache hits, ranked by the service.
///
/// The console's `CacheTopDomains.vue` is the blueprint: a rank badge, the name and its record
/// type, a share bar and the hit count. The list is neither re-sorted nor extended here.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_cache_models.dart';
import 'package:diting/desktop/pages/hub/widgets/cache_common.dart';
import 'package:diting/desktop/pages/logs/log_format.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class CacheTopCard extends StatelessWidget {
  const CacheTopCard({super.key, required this.domains});

  final List<DesktopCacheDomain> domains;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final most = domains.isEmpty
        ? 1
        : domains
              .map((domain) => domain.hitCount)
              .reduce((a, b) => a > b ? a : b);
    return DashboardCard(
      semanticLabel: l10n.desktopCacheTopTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.requests,
            title: l10n.desktopCacheTopTitle,
            leading: [
              DashboardChip(
                label: 'Top ${domains.length}',
                tone: DashboardChipTone.idle,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopCacheTopBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (domains.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.desktopCacheTopEmpty,
                textAlign: TextAlign.center,
                style: DashboardText.label(context),
              ),
            )
          else
            for (final (index, domain) in domains.indexed)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == domains.length - 1 ? 0 : 8,
                ),
                child: _TopRow(
                  rank: index + 1,
                  domain: domain,
                  share: most <= 0 ? 0 : domain.hitCount / most,
                ),
              ),
        ],
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.rank,
    required this.domain,
    required this.share,
  });

  final int rank;
  final DesktopCacheDomain domain;
  final double share;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final leading = rank <= 3;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            spacing: 8,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: leading ? colorScheme.primary : colors.tone,
                  shape: AppShape.all(AppCorner.xs),
                ),
                child: Text(
                  '$rank',
                  maxLines: 1,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .toTabular
                      .copyWith(
                        color: leading
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              Expanded(
                child: Text(
                  domain.domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
              ),
              DashboardChip(label: domain.qtype, tone: DashboardChipTone.idle),
            ],
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: CacheBar(
                  value: share,
                  height: 4,
                  color: colorScheme.tertiary,
                ),
              ),
              Text(
                l10n.desktopCacheTopHits(domain.hitCount),
                maxLines: 1,
                style: DashboardText.label(context),
              ),
              if (domain.lastHitAt > 0)
                Text(
                  desktopClock(
                    DateTime.fromMillisecondsSinceEpoch(domain.lastHitAt)
                        .toLocal(),
                  ),
                  maxLines: 1,
                  style: DashboardText.label(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
