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
/// dropdown only lists the providers selected here; the one in use always stays visible.
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
    final providers = ref
        .watch(dnsProviderCatalogProvider)
        .where((provider) => provider.protocol == protocol)
        .toList(growable: false);
    final settings = ref.watch(legacySettingsProvider);
    final selectedCount = providers
        .where((provider) => _visible(settings, protocol, provider))
        .length;
    final protocolVisible = settings.homeVisibleProtocols.contains(
      protocol.name.toUpperCase(),
    );
    return generateSection(
      title: context.l10n.providerVisibilityProtocol(protocol.label),
      items: [
        ListItem(
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
        ),
        for (final provider in providers)
          ListItem(
            leading: GlyphIcon(
              _visible(settings, protocol, provider)
                  ? AppGlyphs.checkCircle
                  : AppGlyphs.removeCircle,
              size: 20,
            ),
            title: Text(provider.name),
            subtitle: Text(provider.address),
            trailing: CommonCheckBox(
              value: _visible(settings, protocol, provider),
              onChanged: (_) => _toggleProvider(protocol, provider),
            ),
            onTap: () => _toggleProvider(protocol, provider),
          ),
      ],
    );
  }
}
