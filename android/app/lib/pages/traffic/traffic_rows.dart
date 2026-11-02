part of 'traffic_page.dart';

/// One app row: name, package, share bar, up/down bytes. The share bar is hand-drawn from
/// two DecoratedBox widgets, since a LinearProgressIndicator vanishes on the card color.
class AppTrafficRow extends StatelessWidget {
  const AppTrafficRow({
    super.key,
    required this.row,
    required this.total,
    required this.sort,
    required this.onTap,
  });

  final AppTrafficDaily row;
  final int total;

  /// Current sort field. The share bar follows it: sorting by upload while drawing
  /// the total would put bar length and rank out of step.
  final TrafficSort sort;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final highlighted = switch (sort) {
      TrafficSort.total => row.totalBytes,
      TrafficSort.download => row.rxBytes,
      TrafficSort.upload => row.txBytes,
    };

    return ListItem(
      leading: AppIconAvatar(packageName: row.packageName),
      title: Row(
        children: [
          Expanded(
            child: Text(
              row.appName.isEmpty ? row.packageName : row.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            obsFormatBytes(highlighted),
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            ShareBar(share: total <= 0 ? 0 : highlighted / total),
            Text(
              '${row.packageName} · ↓ ${obsFormatBytes(row.rxBytes)} '
              '↑ ${obsFormatBytes(row.txBytes)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
      onTap: onTap,
    );
  }
}

class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.share});

  final double share;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: share.clamp(0.0, 1.0),
                child: ColoredBox(color: colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-app traffic detail (upstream AppTrafficDetailDialog.kt).
class _AppTrafficDetailSheet extends StatelessWidget {
  const _AppTrafficDetailSheet({
    required this.row,
    required this.total,
    required this.sort,
  });

  final AppTrafficDaily row;
  final int total;
  final TrafficSort sort;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final share = row.shareOf(total);
    final highlighted = switch (sort) {
      TrafficSort.total => row.totalBytes,
      TrafficSort.download => row.rxBytes,
      TrafficSort.upload => row.txBytes,
    };

    return CommonScaffold(
      title: row.appName.isEmpty ? row.packageName : row.appName,
      body: ListView(
        // The sheet title floats over the body, so without this gap it covers line one.
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyValueRow(
                    label: context.l10n.trafficPackageName,
                    value: row.packageName,
                    monospace: true,
                  ),
                  if (row.appName.isNotEmpty)
                    KeyValueRow(label: context.l10n.trafficAppName, value: row.appName),
                  KeyValueRow(
                    label: context.l10n.trafficDown,
                    value: obsFormatBytes(row.rxBytes),
                    monospace: true,
                  ),
                  KeyValueRow(
                    label: context.l10n.trafficUp,
                    value: obsFormatBytes(row.txBytes),
                    monospace: true,
                  ),
                  KeyValueRow(
                    label: context.l10n.trafficTotal,
                    value: obsFormatBytes(row.totalBytes),
                    monospace: true,
                  ),
                  KeyValueRow(
                    label: context.l10n.trafficShare,
                    value: '${(share * 100).toStringAsFixed(1)} %',
                    monospace: true,
                  ),
                  KeyValueRow(
                    label: context.l10n.trafficStartDate,
                    // For dateRange and allHistory, date is the earliest day in the group
                    // (upstream min(date)), not the latest update.
                    value: row.date.isEmpty ? '—' : row.date,
                    monospace: true,
                  ),
                  if (row.updatedAt > 0)
                    KeyValueRow(
                      label: context.l10n.trafficLastUpdate,
                      value: _updatedAtLabel(row.updatedAt),
                      monospace: true,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ShareBar(share: share),
          ),
          ListFooter(
            text:
                context.l10n.trafficAttributionFooter,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              context.l10n.trafficShareBarTooltip(
                sort.label(context.l10n),
                obsFormatBytes(highlighted),
              ),
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  /// updated_at is a millisecond timestamp, shown as `yyyy-MM-dd HH:mm`.
  static String _updatedAtLabel(int millis) {
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// Upstream TrafficAttributionDialog.kt: why this app is credited and why no live rate.
class _AttributionSheet extends StatelessWidget {
  const _AttributionSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonScaffold(
      title: context.l10n.trafficAttributionTitle,
      body: ListView(
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Text(context.l10n.trafficScopeTitle, style: context.listTitleStyle),
                  Text(
                    context.l10n.trafficScopeBody,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const Divider(height: 1),
                  Text(context.l10n.trafficWhyLowerTitle, style: context.listTitleStyle),
                  Text(
                    context.l10n.trafficWhyLowerBody,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const Divider(height: 1),
                  Text(context.l10n.trafficWhyNoRateTitle, style: context.listTitleStyle),
                  Text(
                    context.l10n.trafficWhyNoRateBody,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const Divider(height: 1),
                  Text(context.l10n.trafficRetentionTitle, style: context.listTitleStyle),
                  Text(
                    context.l10n.trafficRetentionBody,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const Divider(height: 1),
                  Text(context.l10n.trafficSystemAppsTitle, style: context.listTitleStyle),
                  Text(
                    context.l10n.trafficSystemAppsBody,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          ListFooter(
            text:
                context.l10n.trafficUpstreamFooter,
          ),
        ],
      ),
    );
  }
}
