part of 'traffic_page.dart';

/// Ranges with no data source stay visible but disabled, so upstream parity stays visible.
class _RangeOption {
  const _RangeOption({
    required this.label,
    this.window,
    this.unavailableReason,
  });

  final String label;

  /// null means this option is unavailable in this build (see [unavailableReason]).
  final TrafficWindow? window;

  final String? unavailableReason;
}

/// The five upstream TrafficTimeRange values. "This session" has no source here: the daily
/// table stores one row per app per day, with no in-process running total.
List<_RangeOption> _rangeOptions(AppL10n l10n) => <_RangeOption>[
  _RangeOption(
    label: l10n.trafficSessionRange,
    unavailableReason: l10n.trafficSessionUnavailable,
  ),
  _RangeOption(label: l10n.commonToday, window: TrafficWindow.today),
  _RangeOption(label: l10n.trafficWindowWeek, window: TrafficWindow.week),
  _RangeOption(label: l10n.trafficWindowMonth, window: TrafficWindow.month),
  _RangeOption(label: l10n.trafficAllHistory, window: TrafficWindow.all),
];

/// The four upstream TrafficSortMode values, matching AppTrafficStatsModels.kt.
List<_SortOption> _sortOptions(AppL10n l10n) => <_SortOption>[
  _SortOption(label: l10n.trafficSortTotal, sort: TrafficSort.total),
  _SortOption(label: l10n.trafficSortDownload, sort: TrafficSort.download),
  _SortOption(label: l10n.trafficSortUpload, sort: TrafficSort.upload),
  _SortOption(
    label: l10n.trafficLiveRate,
    unavailableReason: l10n.trafficLiveRateUnavailable,
  ),
];

class _SortOption {
  const _SortOption({required this.label, this.sort, this.unavailableReason});

  final String label;
  final TrafficSort? sort;
  final String? unavailableReason;
}

/// Filter bar: search, sort, hide system apps (upstream TrafficFilterBar.kt). Search sits
/// in the body rather than the app bar, matching upstream's inline RuleSearchField.
class _TrafficFilterBar extends StatelessWidget {
  const _TrafficFilterBar({
    required this.searchController,
    required this.sort,
    required this.hideSystemApps,
    required this.onSearchChanged,
    required this.onSortSelected,
    required this.onHideSystemAppsChanged,
  });

  final TextEditingController searchController;
  final TrafficSort sort;
  final bool hideSystemApps;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_SortOption> onSortSelected;
  final ValueChanged<bool> onHideSystemAppsChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledInputTheme(
            child: TextField(
              controller: searchController,
              autocorrect: false,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: context.l10n.trafficSearchPlaceholder,
                prefixIcon: GlyphIcon(AppGlyphs.search),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // Same ChipRow shape as the range row above: a bare Wrap leaves TonalChip at its
          // 18dp text height, and it wraps to a second line on narrow screens.
          child: ChipRow(
            children: [
              for (final option in _sortOptions(context.l10n))
                FilterPill(
                  label: option.label,
                  selected: option.sort == sort,
                  disabled: option.unavailableReason != null,
                  onPressed: () => onSortSelected(option),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CommonCard(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: ListItem.toggle(
              leading: const GlyphIcon(AppGlyphs.appsList, size: 20),
              title: Text(context.l10n.trafficHideSystemApps),
              subtitle: Text(context.l10n.trafficHideSystemAppsSubtitle),
              value: hideSystemApps,
              onChanged: (value) => onHideSystemAppsChanged(value),
            ),
          ),
        ),
      ],
    );
  }
}

/// Attribution explainer entry (upstream AttributionBannerCard).
class _AttributionBanner extends StatelessWidget {
  const _AttributionBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CommonCard(
        onPressed: onTap,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            GlyphIcon(AppGlyphs.info, size: 18, color: colorScheme.warning),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    context.l10n.trafficWhyDaemonTitle,
                    style: context.listTitleStyle,
                  ),
                  Text(
                    context.l10n.trafficWhyDaemonBody,
                    style: context.listCaptionStyle,
                  ),
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
      ),
    );
  }
}

/// Live rate block: show the native rate when available, otherwise say so. The monitor only
/// covers the current session, so the label must say "this session".
class _LiveRateCard extends ConsumerWidget {
  const _LiveRateCard({required this.windowLabel, required this.showNote});

  final String windowLabel;

  /// Whether to show the note comparing the live rate with the window totals.
  final bool showNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final series = ref.watch(speedSeriesProvider);
    final last = series.last;
    final missing = series.unsupported;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CommonCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Row(
              spacing: 8,
              children: [
                GlyphIcon(
                  AppGlyphs.speed,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                Text(
                  context.l10n.trafficLiveRateTitle,
                  style: context.listTitleStyle,
                ),
              ],
            ),
            if (missing)
              Text(
                context.l10n.trafficNoLiveRate(windowLabel),
                style: context.listCaptionStyle,
              )
            else ...[
              Text(
                series.samples.isEmpty
                    ? '—'
                    : '↓ ${obsFormatBytes(last.down.round())} /s   '
                          '↑ ${obsFormatBytes(last.up.round())} /s',
                style: context.listTitleStyle,
              ),
              if (showNote)
                Text(
                  context.l10n.trafficLiveRateBody(windowLabel),
                  style: context.listCaptionStyle,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Package-prefix fallback for system apps. The traffic table has no isSystem column, so
/// upstream also falls back to this list (AppTrafficStatsViewModel.isSystemApp).
const _knownSystemPrefixes = <String>[
  'android',
  'com.android.',
  'android.uid.',
  'com.google.android.gms',
  'com.google.android.gsf',
  'com.google.android.ext.services',
  'com.google.android.networkstack',
  'com.google.android.providers.media.module',
  'com.miui.',
  'com.xiaomi.',
  'com.huawei.',
  'com.hihonor.',
  'com.coloros.',
  'com.heytap.',
  'com.oplus.',
  'com.vivo.',
  'com.bbk.',
  'com.samsung.',
  'com.sec.',
  'com.lenovo.',
  'com.motorola.',
  'com.meizu.',
  'com.qualcomm.',
  'com.qti.',
  'com.mediatek.',
];

bool isKnownSystemPackagePrefix(String packageName) {
  if (packageName.trim().isEmpty) return false;
  if (packageName == 'android') return true;
  for (final prefix in _knownSystemPrefixes) {
    if (packageName.startsWith(prefix)) return true;
  }
  return false;
}
