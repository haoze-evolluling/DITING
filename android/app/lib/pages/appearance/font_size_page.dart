// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/layout.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Text scale, shown against a live sample so the effect is visible before leaving the page.
class FontSizePage extends ConsumerWidget {
  const FontSizePage({super.key});

  /// Slider granularity: 0.8→1.4 in 5% steps keeps the presets below reachable by dragging.
  static const _step = 0.05;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(textScaleProvider);
    void set(double value) => ref.read(textScaleProvider.notifier).set(value);
    final isDefault = (scale - 1).abs() < 0.001;
    return CommonScaffold(
      title: context.l10n.appearanceFontSizeLabel,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.reset,
          tooltip: context.l10n.fontSizeRestoreDefaults,
          onPressed: isDefault ? null : () => set(1),
        ),
      ],
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _SizePreview(scale: scale),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CommonCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      GlyphIcon(
                        AppGlyphs.textSize,
                        size: 20,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.l10n.appearanceFontSizeLabel,
                          style: context.listTitleStyle,
                        ),
                      ),
                      Text(
                        '${(scale * 100).round()}%',
                        style: context.listSubtitleStyle.copyWith(
                          fontFeatures: appTabularFigures,
                          color: context.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: scale,
                    min: minTextScale,
                    max: maxTextScale,
                    divisions: ((maxTextScale - minTextScale) / _step).round(),
                    label: '${(scale * 100).round()}%',
                    onChanged: set,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          '${(minTextScale * 100).round()}%',
                          style: context.listCaptionStyle,
                        ),
                        const Spacer(),
                        Text(
                          '${(maxTextScale * 100).round()}%',
                          style: context.listCaptionStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedControl<double>(
              segments: [
                (0.85, context.l10n.fontSizeSmall),
                (1.0, context.l10n.fontSizeStandard),
                (1.2, context.l10n.fontSizeLarge),
                (1.4, context.l10n.fontSizeExtraLarge),
              ],
              value: _nearestPreset(scale),
              onChanged: set,
            ),
          ),
          ListFooter(text: context.l10n.fontSizeFooter),
        ],
      ),
    );
  }

  /// The segmented control highlights one option at a time; a dragged value between presets
  /// highlights none, which reads as "custom" without needing a fifth segment.
  static double _nearestPreset(double scale) {
    const presets = [0.85, 1.0, 1.2, 1.4];
    for (final preset in presets) {
      if ((scale - preset).abs() < 0.001) {
        return preset;
      }
    }
    return -1;
  }
}

/// The sample itself: three text levels in one card, so the relative rhythm between title, body and
/// caption is visible at a glance.
class _SizePreview extends StatelessWidget {
  const _SizePreview({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(context.l10n.fontSizePreview, style: context.listCaptionStyle)),
              TonalChip(
                label: '${(scale * 100).round()}%',
                color: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.appearancePoem,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.title2.of(context, emphasized: true),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.appearancePoemBody,
            style: AppTextStyle.body.of(context),
          ),
          const SizedBox(height: 6),
          Text(
            'The quick brown fox jumps over the lazy dog · 0123456789',
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: appTabularFigures,
                ),
          ),
        ],
      ),
    );
  }
}
