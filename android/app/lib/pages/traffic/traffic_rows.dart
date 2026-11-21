part of 'traffic_page.dart';

int _highlightedBytes(AppTrafficDaily row, TrafficSort sort) => switch (sort) {
  TrafficSort.total => row.totalBytes,
  TrafficSort.download => row.rxBytes,
  TrafficSort.upload => row.txBytes,
};

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

  final TrafficSort sort;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final highlighted = _highlightedBytes(row, sort);

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
            style: AppTextRole.supportingText
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
      trailing: const Icon(TablerIcons.chevron_right, size: 18),
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
      borderRadius: AppRadius.standard,
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
    final highlighted = _highlightedBytes(row, sort);

    return CommonScaffold(
      title: row.appName.isEmpty ? row.packageName : row.appName,
      body: ListView(
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
                    tabular: true,
                  ),
                  if (row.appName.isNotEmpty)
                    KeyValueRow(
                      label: context.l10n.trafficAppName,
                      value: row.appName,
                    ),
                  KeyValueRow(
                    label: context.l10n.trafficDown,
                    value: obsFormatBytes(row.rxBytes),
                    tabular: true,
                  ),
                  KeyValueRow(
                    label: context.l10n.trafficUp,
                    value: obsFormatBytes(row.txBytes),
                    tabular: true,
                  ),
                  KeyValueRow(
                    label: context.l10n.trafficTotal,
                    value: obsFormatBytes(row.totalBytes),
                    tabular: true,
                  ),
                  KeyValueRow(
                    label: context.l10n.trafficShare,
                    value: '${(share * 100).toStringAsFixed(1)} %',
                    tabular: true,
                  ),
                  KeyValueRow(
                    label: context.l10n.trafficStartDate,
                    value: row.date.isEmpty ? '—' : row.date,
                    tabular: true,
                  ),
                  if (row.updatedAt > 0)
                    KeyValueRow(
                      label: context.l10n.trafficLastUpdate,
                      value: _updatedAtLabel(row.updatedAt),
                      tabular: true,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ShareBar(share: share),
          ),
          ListFooter(text: context.l10n.trafficAttributionFooter),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              context.l10n.trafficShareBarTooltip(
                sort.label(context.l10n),
                obsFormatBytes(highlighted),
              ),
              style: AppTextRole.supportingText
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static String _updatedAtLabel(int millis) {
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

class _AttributionSheet extends StatelessWidget {
  const _AttributionSheet();

  @override
  Widget build(BuildContext context) {
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
                  _AttributionSection(
                    title: context.l10n.trafficScopeTitle,
                    body: context.l10n.trafficScopeBody,
                  ),
                  const Divider(height: 1),
                  _AttributionSection(
                    title: context.l10n.trafficWhyLowerTitle,
                    body: context.l10n.trafficWhyLowerBody,
                  ),
                  const Divider(height: 1),
                  _AttributionSection(
                    title: context.l10n.trafficWhyNoRateTitle,
                    body: context.l10n.trafficWhyNoRateBody,
                  ),
                  const Divider(height: 1),
                  _AttributionSection(
                    title: context.l10n.trafficRetentionTitle,
                    body: context.l10n.trafficRetentionBody,
                  ),
                  const Divider(height: 1),
                  _AttributionSection(
                    title: context.l10n.trafficSystemAppsTitle,
                    body: context.l10n.trafficSystemAppsBody,
                  ),
                ],
              ),
            ),
          ),
          ListFooter(text: context.l10n.trafficUpstreamFooter),
        ],
      ),
    );
  }
}

class _AttributionSection extends StatelessWidget {
  const _AttributionSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(title, style: AppTextRole.rowTitle.of(context)),
        Text(
          body,
          style: AppTextRole.body
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
