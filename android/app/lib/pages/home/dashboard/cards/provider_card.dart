import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/widgets/dashboard/dashboard_card.dart';
import 'package:diting_android/widgets/dashboard/dashboard_density.dart';
import 'package:diting_android/pages/home/widgets/provider_sheet.dart';
import 'package:diting_android/state/appearance_providers.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
            glyph: TablerIcons.cloud_upload,
            title: single
                ? context.l10n.homeProviderSingleLabel
                : context.l10n.homeProviderRaceLabel,
            trailing: [
              Icon(
                TablerIcons.chevron_right,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextRole.body
                .of(context)
                .copyWith(color: colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
