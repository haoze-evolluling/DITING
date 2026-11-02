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
  late Set<String> _visibleProtocols;
  late Set<String> _hiddenProviders;
  late Set<String> _explicitVisible;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(legacySettingsProvider);
    _visibleProtocols = {...settings.homeVisibleProtocols};
    _hiddenProviders = {...settings.homeHiddenProviderIds};
    _explicitVisible = {...settings.homeVisibleProviderIds};
  }

  void _save() {
    ref
        .read(legacySettingsProvider)
        .setHomeProviderVisibility(
          visibleProtocols: _visibleProtocols,
          hiddenProviderIds: _hiddenProviders,
          visibleProviderIds: _explicitVisible,
        );
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  bool _visible(ProviderProtocol protocol, MockProvider provider) =>
      _visibleProtocols.contains(protocol.name.toUpperCase())
      ? !_hiddenProviders.contains(provider.id)
      : _explicitVisible.contains(provider.id);

  /// Toggles one provider. Under a visible protocol it is a "hide" flag; under a hidden
  /// protocol it is the explicit allow-list upstream keeps.
  void _toggleProvider(ProviderProtocol protocol, MockProvider provider) {
    setState(() {
      if (_visibleProtocols.contains(protocol.name.toUpperCase())) {
        if (!_hiddenProviders.remove(provider.id)) {
          _hiddenProviders.add(provider.id);
        }
      } else {
        if (!_explicitVisible.remove(provider.id)) {
          _explicitVisible.add(provider.id);
        }
      }
    });
    _save();
  }

  void _setProtocol(ProviderProtocol protocol, bool visible) {
    setState(() {
      if (visible) {
        _visibleProtocols.add(protocol.name.toUpperCase());
        // Re-enabling a group clears the per-provider overrides inside it.
        _hiddenProviders.removeAll(
          ref
              .read(dnsProviderCatalogProvider)
              .where((provider) => provider.protocol == protocol)
              .map((provider) => provider.id),
        );
      } else {
        _visibleProtocols.remove(protocol.name.toUpperCase());
        _explicitVisible.removeAll(
          ref
              .read(dnsProviderCatalogProvider)
              .where((provider) => provider.protocol == protocol)
              .map((provider) => provider.id),
        );
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.providerVisibilityTitle,
      body: PageBody(
        children: [
          PageIntroCard(
            text:
                context.l10n.providerVisibilityNote,
          ),
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
    final selectedCount = providers
        .where((provider) => _visible(protocol, provider))
        .length;
    final protocolVisible = _visibleProtocols.contains(
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
              _visible(protocol, provider)
                  ? AppGlyphs.checkCircle
                  : AppGlyphs.removeCircle,
              size: 20,
            ),
            title: Text(provider.name),
            subtitle: Text(provider.address),
            trailing: CommonCheckBox(
              value: _visible(protocol, provider),
              onChanged: (_) => _toggleProvider(protocol, provider),
            ),
            onTap: () => _toggleProvider(protocol, provider),
          ),
      ],
    );
  }
}
