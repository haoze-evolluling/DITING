import 'package:diting_android/data/vpn/cache_presets.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class CachePresetCard extends StatelessWidget {
  const CachePresetCard({
    super.key,
    required this.tier,
    required this.selected,
    required this.scalePercent,
    required this.onPressed,
    required this.onScaleChanged,
  });

  final DnsCacheTier tier;
  final bool selected;
  final int scalePercent;
  final VoidCallback onPressed;
  final ValueChanged<int> onScaleChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final percent = tier.isCustom ? scalePercent : tier.defaultScalePercent;
    return CommonCard(
      isSelected: selected,
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 12,
            children: [
              IconBadge(
                glyph: _glyphOf(tier),
                size: 40,
                glyphSize: 22,
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.14)
                    : colorScheme.surfaceContainerHigh,
                foregroundColor: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          tier.label(l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextRole.cardTitle.of(context),
                        ),
                        MetaChip(
                          label: l10n.cachePresetMultiplier(
                            formatCacheScale(percent),
                          ),
                        ),
                        if (tier == DnsCacheTier.standard)
                          TonalChip(
                            label: l10n.cachePresetRecommended,
                            color: colorScheme.primary.withValues(alpha: 0.14),
                            foregroundColor: colorScheme.primary,
                          ),
                      ],
                    ),
                    Text(
                      tier.summary(l10n),
                      style: AppTextRole.supportingText
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (selected)
                const SelectionCheck()
              else
                const SizedBox(width: SelectionCheck.size),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            cachePresetExampleText(l10n, percent),
            style: AppTextRole.caption
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          AnimatedSize(
            duration: context.motionDuration(commonDuration),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: selected && tier.isCustom
                ? _ScaleEditor(scalePercent: percent, onChanged: onScaleChanged)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  static Glyph _glyphOf(DnsCacheTier tier) => switch (tier) {
    DnsCacheTier.conservative => AppGlyphs.clock,
    DnsCacheTier.standard => AppGlyphs.database,
    DnsCacheTier.aggressive => AppGlyphs.bolt,
    DnsCacheTier.custom => AppGlyphs.sliders,
  };
}

class _ScaleEditor extends StatelessWidget {
  const _ScaleEditor({required this.scalePercent, required this.onChanged});

  final int scalePercent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final multiplier = l10n.cachePresetMultiplier(
      formatCacheScale(scalePercent),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.cacheCustomScaleLabel,
                style: AppTextRole.rowTitle.of(context),
              ),
            ),
            Text(
              multiplier,
              style: AppTextRole.rowTitle
                  .of(context)
                  .copyWith(color: colorScheme.primary),
            ),
          ],
        ),
        Slider(
          value: scalePercent.toDouble(),
          min: DnsCachePolicy.minScalePercent.toDouble(),
          max: DnsCachePolicy.maxScalePercent.toDouble(),
          divisions:
              (DnsCachePolicy.maxScalePercent -
                  DnsCachePolicy.minScalePercent) ~/
              DnsCachePolicy.scaleStepPercent,
          label: multiplier,
          onChanged: (value) =>
              onChanged(DnsCachePolicy.clampScale(value.round())),
        ),
        Text(
          l10n.cacheCustomScaleHint,
          style: AppTextRole.caption
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
