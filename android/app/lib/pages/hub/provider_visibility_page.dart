import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Provider visibility (upstream `HomeProviderVisibilityScreen`). With racing off the home provider
/// dropdown only lists the providers selected here; the one in use always stays visible. The rows
/// also carry the shared display order, which the provider picker uses for both modes.
class ProviderVisibilityPage extends ConsumerStatefulWidget {
  const ProviderVisibilityPage({super.key});

  @override
  ConsumerState<ProviderVisibilityPage> createState() =>
      _ProviderVisibilityPageState();
}

class _ProviderVisibilityPageState
    extends ConsumerState<ProviderVisibilityPage> {
  void _write({
    required Set<String> visibleProtocols,
    required Set<String> hiddenProviderIds,
    required Set<String> visibleProviderIds,
  }) => ref.writeSettings(
    (settings) => settings.setHomeProviderVisibility(
      visibleProtocols: visibleProtocols,
      hiddenProviderIds: hiddenProviderIds,
      visibleProviderIds: visibleProviderIds,
    ),
  );

  /// Reads the sets back from the store on every build instead of mirroring them locally, so a
  /// backup import or another page's write shows up without leaving the page.
  bool _visible(
    LegacySettings settings,
    ProviderProtocol protocol,
    MockProvider provider,
  ) => settings.homeVisibleProtocols.contains(protocol.name.toUpperCase())
      ? !settings.homeHiddenProviderIds.contains(provider.id)
      : settings.homeVisibleProviderIds.contains(provider.id);

  /// Toggles one provider. Under a visible protocol it is a "hide" flag; under a hidden
  /// protocol it is the explicit allow-list upstream keeps.
  void _toggleProvider(ProviderProtocol protocol, MockProvider provider) {
    final settings = ref.read(legacySettingsProvider);
    final protocols = {...settings.homeVisibleProtocols};
    final hidden = {...settings.homeHiddenProviderIds};
    final explicit = {...settings.homeVisibleProviderIds};
    if (protocols.contains(protocol.name.toUpperCase())) {
      if (!hidden.remove(provider.id)) {
        hidden.add(provider.id);
      }
    } else {
      if (!explicit.remove(provider.id)) {
        explicit.add(provider.id);
      }
    }
    _write(
      visibleProtocols: protocols,
      hiddenProviderIds: hidden,
      visibleProviderIds: explicit,
    );
  }

  void _setProtocol(ProviderProtocol protocol, bool visible) {
    final settings = ref.read(legacySettingsProvider);
    final protocols = {...settings.homeVisibleProtocols};
    final hidden = {...settings.homeHiddenProviderIds};
    final explicit = {...settings.homeVisibleProviderIds};
    final ids = [
      for (final provider in ref.read(dnsProviderCatalogProvider))
        if (provider.protocol == protocol) provider.id,
    ];
    if (visible) {
      protocols.add(protocol.name.toUpperCase());
      // Re-enabling a group clears the per-provider overrides inside it.
      hidden.removeAll(ids);
    } else {
      protocols.remove(protocol.name.toUpperCase());
      explicit.removeAll(ids);
    }
    _write(
      visibleProtocols: protocols,
      hiddenProviderIds: hidden,
      visibleProviderIds: explicit,
    );
  }

  /// Moves one row inside its protocol group and writes the group back into the shared order, so
  /// the other protocols keep their slots.
  void _reorder(List<MockProvider> group, int oldIndex, int newIndex) {
    final ordered = orderedProviders(
      ref.read(dnsProviderCatalogProvider),
      ref.read(legacySettingsProvider).providerDisplayOrderIds,
    );
    final next = reorderProviderIds(
      order: [for (final provider in ordered) provider.id],
      groupIds: [for (final provider in group) provider.id],
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    ref.writeSettings((settings) => settings.setProviderDisplayOrderIds(next));
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.providerVisibilityTitle,
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.providerVisibilityNote),
          for (final protocol in ProviderProtocol.values)
            _protocolSection(protocol),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _protocolSection(ProviderProtocol protocol) {
    final settings = ref.watch(legacySettingsProvider);
    final providers =
        orderedProviders(
              ref.watch(dnsProviderCatalogProvider),
              settings.providerDisplayOrderIds,
            )
            .where((provider) => provider.protocol == protocol)
            .toList(growable: false);
    final selectedCount = providers
        .where((provider) => _visible(settings, protocol, provider))
        .length;
    final protocolVisible = settings.homeVisibleProtocols.contains(
      protocol.name.toUpperCase(),
    );
    final allRow = ListItem(
      leading: GlyphIcon(
        protocolVisible ? AppGlyphs.checkCircle : AppGlyphs.removeCircle,
        size: 20,
      ),
      title: Text(context.l10n.providerVisibilityAll(protocol.label)),
      subtitle: Text(
        !protocolVisible
            ? context.l10n.providerVisibilityNone
            : selectedCount == providers.length
            ? context.l10n.providerVisibilityAllOn
            : context.l10n.providerVisibilityCount('$selectedCount'),
      ),
      trailing: CommonCheckBox(
        value: protocolVisible && selectedCount > 0,
        onChanged: (_) => _setProtocol(protocol, !protocolVisible),
      ),
      onTap: () => _setProtocol(protocol, !protocolVisible),
    );
    return Column(
      children: [
        ListHeader(
          title: context.l10n.providerVisibilityProtocol(protocol.label),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ReorderableListView.builder(
            // The page already scrolls; a nested scrollable would steal drag gestures.
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: commonProxyDecorator,
            // The group switch shares the card but never takes part in the ordering.
            header: ItemPositionProvider(
              position: ItemPosition.start,
              child: allRow,
            ),
            itemCount: providers.length,
            onReorderItem: (oldIndex, newIndex) =>
                _reorder(providers, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final provider = providers[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(provider.id),
                index: index,
                child: ItemPositionProvider(
                  position: ItemPosition.get(index, providers.length),
                  child: _ProviderRow(
                    provider: provider,
                    visible: _visible(settings, protocol, provider),
                    index: index,
                    onToggle: () => _toggleProvider(protocol, provider),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One provider row: tap or checkbox toggles it, the trailing handle drags it into order.
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.visible,
    required this.index,
    required this.onToggle,
  });

  final MockProvider provider;
  final bool visible;
  final int index;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: GlyphIcon(
        visible ? AppGlyphs.checkCircle : AppGlyphs.removeCircle,
        size: 20,
      ),
      title: Text(provider.name),
      subtitle: Text(provider.address),
      padding: const EdgeInsets.only(left: 16, right: 4),
      onTap: onToggle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CommonCheckBox(value: visible, onChanged: (_) => onToggle()),
          ReorderableDragStartListener(
            index: index,
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: SizedBox.square(
                dimension: kMinInteractiveDimension,
                child: Center(child: GlyphIcon(AppGlyphs.dragHandle)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
