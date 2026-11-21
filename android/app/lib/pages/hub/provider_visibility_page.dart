import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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

  static String _protocolKey(ProviderProtocol protocol) =>
      protocol.name.toUpperCase();

  bool _visible(
    LegacySettings settings,
    ProviderProtocol protocol,
    MockProvider provider,
  ) => settings.homeVisibleProtocols.contains(_protocolKey(protocol))
      ? !settings.homeHiddenProviderIds.contains(provider.id)
      : settings.homeVisibleProviderIds.contains(provider.id);

  ({Set<String> protocols, Set<String> hidden, Set<String> explicit})
  _visibilitySets() {
    final settings = ref.read(legacySettingsProvider);
    return (
      protocols: {...settings.homeVisibleProtocols},
      hidden: {...settings.homeHiddenProviderIds},
      explicit: {...settings.homeVisibleProviderIds},
    );
  }

  void _toggleProvider(ProviderProtocol protocol, MockProvider provider) {
    final sets = _visibilitySets();
    if (sets.protocols.contains(_protocolKey(protocol))) {
      if (!sets.hidden.remove(provider.id)) {
        sets.hidden.add(provider.id);
      }
    } else {
      if (!sets.explicit.remove(provider.id)) {
        sets.explicit.add(provider.id);
      }
    }
    _write(
      visibleProtocols: sets.protocols,
      hiddenProviderIds: sets.hidden,
      visibleProviderIds: sets.explicit,
    );
  }

  void _setProtocol(ProviderProtocol protocol, bool visible) {
    final sets = _visibilitySets();
    final ids = [
      for (final provider in ref.read(dnsProviderCatalogProvider))
        if (provider.protocol == protocol) provider.id,
    ];
    if (visible) {
      sets.protocols.add(_protocolKey(protocol));
      sets.hidden.removeAll(ids);
    } else {
      sets.protocols.remove(_protocolKey(protocol));
      sets.explicit.removeAll(ids);
    }
    _write(
      visibleProtocols: sets.protocols,
      hiddenProviderIds: sets.hidden,
      visibleProviderIds: sets.explicit,
    );
  }

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
      _protocolKey(protocol),
    );
    final allRow = ListItem(
      leading: Icon(
        protocolVisible ? TablerIcons.circle_check : TablerIcons.circle_minus,
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
        value: protocolVisible,
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
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: commonProxyDecorator,
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
                  position: ItemPosition.get(index + 1, providers.length + 1),
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
      leading: Icon(
        visible ? TablerIcons.circle_check : TablerIcons.circle_minus,
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
                child: Center(child: Icon(TablerIcons.grip_vertical)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
