import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/cache_presets.dart';
import 'package:diting_android/pages/hub/cache_preset_card.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CacheSettingsPage extends ConsumerWidget {
  const CacheSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final enabled = settings.cacheEnabled;
    final policy = DnsCachePolicy.read(settings);
    final l10n = context.l10n;

    void save({bool? enabled, DnsCacheTier? tier, int? scalePercent}) {
      DnsCachePolicy(
        tier: tier ?? policy.tier,
        scalePercent: scalePercent ?? policy.scalePercent,
      ).write(settings, enabled: enabled ?? settings.cacheEnabled);
      ref.read(legacySettingsRevisionProvider.notifier).bump();
    }

    return CommonScaffold(
      title: l10n.cacheSettingsTitle,
      body: PageBody(
        children: [
          generateSection(
            title: l10n.cacheSection,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.database),
                title: Text(l10n.cacheLocalDns),
                subtitle: Text(
                  enabled
                      ? cachePolicySummary(settings, l10n)
                      : l10n.cacheOffNote,
                ),
                value: enabled,
                onChanged: (value) => save(enabled: value),
              ),
            ],
          ),
          if (enabled) ...[
            ListHeader(title: l10n.cachePresetSection),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                spacing: 10,
                children: [
                  for (final tier in DnsCacheTier.values)
                    CachePresetCard(
                      tier: tier,
                      selected: policy.tier == tier,
                      scalePercent: policy.scalePercent,
                      onPressed: () => save(tier: tier),
                      onScaleChanged: (value) => save(scalePercent: value),
                    ),
                ],
              ),
            ),
            ListFooter(text: l10n.cachePresetNote),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
