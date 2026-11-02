import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/pages/home/widgets/provider_sheet.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Service provider card: the active provider in single mode, the race list otherwise. Both this
/// card and the detail entry points open [showProviderSheet], so they cannot drift apart.
class ProviderCard extends ConsumerWidget {
  const ProviderCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolution = ref.watch(resolutionModeProvider);
    final selectedId = ref.watch(selectedProviderProvider);
    final raceIds = ref.watch(raceProvidersProvider);
    final catalog = ref.watch(dnsProviderCatalogProvider);
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    // Edit mode greys the body but would still open the sheet on tap; editing wins.
    final editing = ref.watch(dashboardEditingProvider);
    final single = resolution.isSingle;
    final subtitle = single
        ? endpointOfProvider(selectedId, catalog)
        : summaryOfProviders(raceIds, catalog);
    return DashboardCard(
      semanticLabel: single
          ? context.l10n.homeProviderSingleLabel
          : context.l10n.homeProviderRaceLabel,
      onTap: editing ? null : () => showProviderSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: single
                ? context.l10n.homeProviderSingleLabel
                : context.l10n.homeProviderRaceLabel,
            trailing: [
              GlyphIcon(
                AppGlyphs.chevronForward,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          // Two lines: the race summary lists every picked provider by name.
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.figure(
              context,
              AppTextStyle.subheadline,
              color: colorScheme.onSurface,
            ).copyWith(letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}
