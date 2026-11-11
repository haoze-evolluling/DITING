import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/state/feature_hub_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/glyph_lookup.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Hidden features (upstream `HiddenFeaturesScreen`). Hiding only affects the feature hub
/// and never disables anything; keys persist to `dns_vpn_prefs` / `hidden_features_set`.
class HiddenFeaturesPage extends ConsumerWidget {
  const HiddenFeaturesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final express = ref.watch(workModeProvider) == AppWorkMode.express;
    final hidden = ref.watch(hiddenFeatureKeysProvider);
    final groups = hiddenFeaturesByCategory(
      express: express,
      l10n: context.l10n,
    );
    return CommonScaffold(
      title: context.l10n.hiddenFeaturesTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.reset,
          tooltip: context.l10n.hiddenFeaturesReset,
          onPressed: hidden.isEmpty
              ? null
              : () => ref.read(hiddenFeatureKeysProvider.notifier).resetAll(),
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(
            text:
                context.l10n.hiddenFeaturesNote,
          ),
          for (final entry in groups.entries)
            generateSection(
              title: entry.key,
              items: [
                for (final feature in entry.value)
                  ListItem(
                    leading: GlyphIcon(
                      glyphByName(feature.glyphName),
                      size: 20,
                    ),
                    title: Text(feature.title),
                    subtitle: Text(feature.description),
                    trailing: CommonCheckBox(
                      value: !hidden.contains(feature.key),
                      onChanged: (visible) => ref
                          .read(hiddenFeatureKeysProvider.notifier)
                          .setVisible(feature.key, visible ?? true),
                    ),
                    onTap: () => ref
                        .read(hiddenFeatureKeysProvider.notifier)
                        .toggle(feature.key),
                  ),
              ],
            ),
          ListFooter(text: context.l10n.hiddenFeaturesFooter),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
