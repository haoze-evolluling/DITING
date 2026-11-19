import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the provider picker. Shared by the home provider card and the provider management
/// entry points, so the two cannot drift apart.
void showProviderSheet(BuildContext context) =>
    showSheet<void>(context: context, builder: (_) => const ProviderSheet());

/// The sheet keeps the active provider even after it left the catalog.
class ProviderSheet extends ConsumerStatefulWidget {
  const ProviderSheet({super.key});

  @override
  ConsumerState<ProviderSheet> createState() => _ProviderSheetState();
}

class _ProviderSheetState extends ConsumerState<ProviderSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    if (ref.read(raceProvidersProvider.notifier).toggle(id)) {
      return;
    }
    // The last two providers stay selected; say why instead of dropping the tap silently.
    showAppSnack(context, context.l10n.resolutionMinProviders);
  }

  List<MockProvider> _filter(List<MockProvider> providers) {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) {
      return providers;
    }
    return [
      for (final provider in providers)
        if (provider.name.toLowerCase().contains(needle) ||
            provider.address.toLowerCase().contains(needle) ||
            provider.protocol.label.toLowerCase().contains(needle))
          provider,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final resolution = ref.watch(resolutionModeProvider);
    final selectedId = ref.watch(selectedProviderProvider);
    final raceIds = ref.watch(raceProvidersProvider);
    final single = resolution.isSingle;
    final visible = _filter(ref.watch(visibleProvidersProvider));
    final groups = [
      for (final protocol in ProviderProtocol.values)
        (
          protocol,
          [
            for (final provider in visible)
              if (provider.protocol == protocol) provider,
          ],
        ),
    ];
    return CommonScaffold(
      title: single
          ? context.l10n.providerSheetSingleTitle
          : context.l10n.providerSheetRaceTitle,
      body: ListView(
        // The sheet title floats over the body, so this top padding is required.
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          if (!single) _RaceSummary(count: raceIds.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SearchField(
              controller: _search,
              hintText: context.l10n.providerSheetSearchHint,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (visible.isEmpty)
            ListFooter(
              text: _query.trim().isEmpty
                  ? context.l10n.resolutionNoProviders
                  : UiLocalizations.of(context).noSearchResults,
            )
          else
            // Providers keep the arranged display order inside each protocol, the same
            // grouping the visibility page edits.
            for (final (protocol, providers) in groups)
              if (providers.isNotEmpty)
                generateSection(
                  title: protocol.label,
                  items: [
                    for (final provider in providers)
                      _providerRow(
                        provider,
                        single: single,
                        selectedId: selectedId,
                        raceIds: raceIds,
                      ),
                  ],
                ),
          // Two action items share the list and position with the providers. Close the
          // sheet before pushing, otherwise returning shows it again and looks stuck.
          const ListSectionGap(),
          generateSection(
            items: [
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
            ],
          ),
          ListFooter(
            text: single
                ? context.l10n.providerSheetSingleFooter
                : context.l10n.providerSheetRaceFooter,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TonalButton(
              label: context.l10n.providerSheetDone,
              glyph: AppGlyphs.check,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerRow(
    MockProvider provider, {
    required bool single,
    required String selectedId,
    required Set<String> raceIds,
  }) {
    final selected = single
        ? selectedId == provider.id
        : raceIds.contains(provider.id);
    return ListItem(
      leading: const _ProviderMark(),
      title: Text(provider.name),
      subtitle: Text(
        provider.address,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          // Racing picks the fastest resolver, so the last measured latency helps here. A
          // provider that was never probed would only add "未测速" noise to every row.
          if (!single && provider.latencyMs >= 0)
            Text(
              providerLatencyLabel(provider),
              style: AppTextStyle.caption1.of(context).toTabular,
            ),
          if (single)
            selected
                ? const SelectionCheck()
                : Text(
                    providerLatencyLabel(provider),
                    style: AppTextStyle.caption1.of(context).toTabular,
                  )
          else
            CommonCheckBox(
              value: selected,
              isCircle: true,
              onChanged: (_) => _toggle(provider.id),
            ),
        ],
      ),
      onTap: single
          ? () {
              ref.read(selectedProviderProvider.notifier).select(provider.id);
              Navigator.of(context).pop();
            }
          : () => _toggle(provider.id),
    );
  }
}

/// Why the race list asks for two providers, with the current count and whether it is met.
class _RaceSummary extends StatelessWidget {
  const _RaceSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final ready = count >= RaceProvidersNotifier.minCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          spacing: 12,
          children: [
            GlyphIcon(AppGlyphs.speed, size: 22, color: colorScheme.primary),
            Expanded(
              child: Text(
                context.l10n.resolutionRaceHint(count),
                style: context.listSubtitleStyle,
              ),
            ),
            _RaceStatusChip(ready: ready),
          ],
        ),
      ),
    );
  }
}

/// The neutral well an identifying glyph sits on; built inside the row so it takes the block
/// level above the card instead of the card's own fill.
class _ProviderMark extends StatelessWidget {
  const _ProviderMark();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.standard,
      ),
      child: Center(
        child: GlyphIcon(
          AppGlyphs.upstream,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RaceStatusChip extends StatelessWidget {
  const _RaceStatusChip({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return TonalChip(
      label: ready
          ? context.l10n.resolutionReady
          : context.l10n.resolutionPending,
      color: ready
          ? colorScheme.primary
          : context.raisedSurfaceLevel.colorOf(colorScheme),
      foregroundColor: ready
          ? colorScheme.onPrimary
          : colorScheme.onSurfaceVariant,
    );
  }
}
