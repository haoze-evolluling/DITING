/// The cache exclude rules: the domains that must bypass the cache entirely.
///
/// The old desktop console's `CacheExcludeCard.vue` is the blueprint: one Go RE2 expression per
/// line, the same three presets, the same 256-rule and 512-character bounds, and a save button that
/// only lights up once the text differs from what the service holds.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/data/api/desktop_cache_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The service's own bounds, repeated here so a reader sees the truncation before saving.
const int _maxPatterns = 256;
const int _maxPatternLength = 512;

const _presetLocal = r'\.local$';
const _presetPtr = r'^\d+\.\d+\.\d+\.\d+\.in-addr\.arpa$';
const _presetProbe = r'^time\.|^connectivity-check\.';

class CacheExcludeCard extends ConsumerStatefulWidget {
  const CacheExcludeCard({super.key, required this.persist});

  final DesktopCachePersist? persist;

  @override
  ConsumerState<CacheExcludeCard> createState() => _CacheExcludeCardState();
}

class _CacheExcludeCardState extends ConsumerState<CacheExcludeCard> {
  final _draft = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  List<String> get _parsed => [
    for (final line in _draft.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  Future<void> _save(List<String> patterns) async {
    final l10n = context.l10n;
    final config = ref.read(desktopCacheConfigProvider).config;
    if (config == null) return;
    final error = await ref
        .read(desktopCacheConfigProvider.notifier)
        .save(config.copyWith(excludePatterns: patterns));
    if (!mounted) return;
    if (error != null) {
      showDesktopMessage(
        context,
        l10n.desktopCacheExcludeFailed(error.message),
      );
      return;
    }
    await ref.read(desktopCacheSnapshotProvider.notifier).refresh();
    if (!mounted) return;
    showDesktopMessage(
      context,
      patterns.isEmpty
          ? l10n.desktopCacheExcludeCleared
          : l10n.desktopCacheExcludeSaved(patterns.length),
    );
  }

  void _addPreset(String pattern) {
    if (_parsed.contains(pattern)) return;
    _draft.text = [..._parsed, pattern].join('\n');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopCacheConfigProvider);
    final config = state.config;
    if (config != null && !_seeded) {
      _seeded = true;
      _draft.text = config.excludePatterns.join('\n');
    }
    final parsed = _parsed;
    final dirty =
        config != null &&
        parsed.join('\n') != config.excludePatterns.join('\n');
    final tooMany = parsed.length > _maxPatterns;
    final tooLong = parsed
        .where((pattern) => pattern.length > _maxPatternLength)
        .length;
    final presets = [
      (l10n.desktopCacheExcludePresetLocal, _presetLocal),
      (l10n.desktopCacheExcludePresetPtr, _presetPtr),
      (l10n.desktopCacheExcludePresetProbe, _presetProbe),
    ];
    return DashboardCard(
      semanticLabel: l10n.desktopCacheExcludeTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.block,
            title: l10n.desktopCacheExcludeTitle,
            leading: [
              DashboardChip(
                label: parsed.isEmpty
                    ? l10n.desktopCacheExcludeOff
                    : l10n.desktopCacheExcludeCount(parsed.length),
                tone: parsed.isEmpty
                    ? DashboardChipTone.idle
                    : DashboardChipTone.ok,
              ),
            ],
            trailing: [
              if (state.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardIconButton(
                  glyph: AppGlyphs.check,
                  tooltip: l10n.desktopCacheExcludeSave,
                  onPressed: config == null || !dirty
                      ? null
                      : () => unawaited(_save(parsed)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopCacheExcludeBody,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _draft,
            minLines: 4,
            maxLines: 6,
            enabled: config != null && !state.saving,
            style: AppTextStyle.caption1.of(context).toTabular,
            decoration: InputDecoration(
              labelText: l10n.desktopCacheExcludeLabel,
              hintText: l10n.desktopCacheExcludeHint,
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (tooMany || tooLong > 0) ...[
            const SizedBox(height: 6),
            for (final problem in [
              if (tooMany) l10n.desktopCacheExcludeTooMany(_maxPatterns),
              if (tooLong > 0)
                l10n.desktopCacheExcludeTooLong(tooLong, _maxPatternLength),
            ])
              Text(
                problem,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: context.colorScheme.warning),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (label, pattern) in presets)
                TonalButton(
                  size: TonalButtonSize.compact,
                  label: label,
                  onPressed: config == null || state.saving
                      ? null
                      : () => _addPreset(pattern),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.desktopCacheExcludeHits(widget.persist?.excludeHits ?? 0),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (dirty)
                TonalButton(
                  size: TonalButtonSize.compact,
                  glyph: AppGlyphs.undo,
                  label: l10n.desktopCacheExcludeReset,
                  onPressed: () {
                    _draft.text = config.excludePatterns.join('\n');
                    setState(() {});
                  },
                ),
              TonalButton(
                size: TonalButtonSize.compact,
                glyph: AppGlyphs.check,
                label: l10n.desktopCacheExcludeSave,
                onPressed: config == null || !dirty || state.saving
                    ? null
                    : () => unawaited(_save(parsed)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
