import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Resolution mode card: segmented control, explanation, current endpoints. It replaced the fixed
/// home block, so it drags, removes and adds like the other dashboard cards.
class ResolutionCard extends ConsumerWidget {
  const ResolutionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolution = ref.watch(resolutionModeProvider);
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    // Edit mode greys the body only; the segmented control would still switch modes on tap.
    final editing = ref.watch(dashboardEditingProvider);
    return DashboardCard(
      semanticLabel: context.l10n.resolutionModeTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.shuffle,
            title: context.l10n.resolutionModeTitle,
            trailing: [
              Text(
                resolution.label(context.l10n),
                style: AppTextStyle.footnote
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.primary),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          IgnorePointer(
            ignoring: editing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedControl<ResolutionMode>(
                  segments: [
                    for (final option in ResolutionMode.values)
                      (option, option.label(context.l10n)),
                  ],
                  value: resolution,
                  onChanged: (value) =>
                      ref.read(resolutionModeProvider.notifier).select(value),
                ),
                SizedBox(height: 8 * scale),
                Text(
                  describeResolutionMode(resolution, context.l10n),
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(height: 10 * scale),
          DashboardBlock(
            padding: EdgeInsets.symmetric(
              horizontal: 12 * scale,
              vertical: 9 * scale,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1 * scale),
                  child: GlyphIcon(
                    AppGlyphs.dns,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      for (final line in ref.watch(_endpointLinesProvider))
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardText.label(context),
                        ),
                    ],
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

/// One line per endpoint in use, in the order the engine tries them (primary first), so the card
/// matches the resolution page; single mode has just one.
final _endpointLinesProvider = Provider<List<String>>((ref) {
  final resolution = ref.watch(resolutionModeProvider);
  final selectedId = ref.watch(selectedProviderProvider);
  final raceIds = ref.watch(raceProvidersProvider);
  final catalog = ref.watch(dnsProviderCatalogProvider);
  final byId = {for (final provider in catalog) provider.id: provider};
  final endpoints = resolution.isSingle
      ? [endpointOfProvider(selectedId, catalog)]
      : [
          for (final id in raceIds)
            if (byId[id] case final provider?)
              '${provider.protocol.label} · ${provider.address}',
        ];
  return endpoints.isEmpty ? [currentL10n.resolutionNoProvider] : endpoints;
});

/// One-line explanation of what the selected mode actually does.
String describeResolutionMode(ResolutionMode mode, AppL10n l10n) =>
    switch (mode) {
      ResolutionMode.single => l10n.resolutionSingleSummary,
      ResolutionMode.smart => l10n.resolutionSmartSummary,
      ResolutionMode.parallel => l10n.resolutionParallelSummary,
      ResolutionMode.primaryBackup => l10n.resolutionPrimaryBackupSummary,
    };
