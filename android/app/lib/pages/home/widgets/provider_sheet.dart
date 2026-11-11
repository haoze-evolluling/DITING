import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/glyph_lookup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the provider picker. Shared by the home provider card and the provider management
/// entry points, so the two cannot drift apart.
void showProviderSheet(BuildContext context) =>
    showSheet<void>(context: context, builder: (_) => const ProviderSheet());

/// The sheet keeps the active provider even after it left the catalog.
class ProviderSheet extends ConsumerWidget {
  const ProviderSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolution = ref.watch(resolutionModeProvider);
    final selectedId = ref.watch(selectedProviderProvider);
    final raceIds = ref.watch(raceProvidersProvider);
    final visible = ref.watch(visibleProvidersProvider);
    return CommonScaffold(
      title: resolution.isSingle
          ? context.l10n.providerSheetSingleTitle
          : context.l10n.providerSheetRaceTitle,
      body: ListView(
        // The sheet title floats over the body, so this top padding is required.
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          ListHeader(
            title: resolution.isSingle
                ? context.l10n.providerSheetSingleOptions
                : context.l10n.providerSheetRaceMinimum,
          ),
          for (final provider in visible)
            ListItem(
              leading: GlyphIcon(glyphByName('dns'), size: 20),
              title: Text(provider.name),
              subtitle: Text(
                '${provider.protocol.label} · ${provider.address}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: resolution.isSingle
                  ? (selectedId == provider.id
                        ? const SelectionCheck()
                        : Text(
                            providerLatencyLabel(provider),
                            style: AppTextStyle.caption1.of(context),
                          ))
                  : CommonCheckBox(
                      value: raceIds.contains(provider.id),
                      isCircle: true,
                      onChanged: (_) => ref
                          .read(raceProvidersProvider.notifier)
                          .toggle(provider.id),
                    ),
              onTap: resolution.isSingle
                  ? () {
                      ref
                          .read(selectedProviderProvider.notifier)
                          .select(provider.id);
                      Navigator.of(context).pop();
                    }
                  : () => ref
                        .read(raceProvidersProvider.notifier)
                        .toggle(provider.id),
            ),
          // Two action items share the list and position with the providers. Close the
          // sheet before pushing, otherwise returning shows it again and looks stuck.
          ListItem(
            leading: const GlyphIcon(AppGlyphs.settings, size: 20),
            title: Text(context.l10n.providerSheetManage),
            trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
            onTap: () {
              Navigator.of(context).pop();
              context.push(HubPaths.providerManagement);
            },
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.eye, size: 20),
            title: Text(context.l10n.providerSheetVisibility),
            trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
            onTap: () {
              Navigator.of(context).pop();
              context.push(HubPaths.providerVisibility);
            },
          ),
          ListFooter(
            text: resolution.isSingle
                ? context.l10n.providerSheetSingleFooter
                : context.l10n.providerSheetRaceFooter,
          ),
        ],
      ),
    );
  }
}
