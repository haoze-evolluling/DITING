/// The temporary pause: the console's `RulesPanel.vue` header block. Pausing stops every rule until
/// the chosen duration ends (or until resumed by hand), and a service restart clears it.
///
/// The switch and the duration are a local choice; the pause itself is the service's runtime state,
/// re-read after every call.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_filter_config_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/desktop/widgets/desktop_picker.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The four durations the console offers, in minutes.
const List<int> desktopPauseMinutes = [5, 30, 60, 480];

String _durationLabel(BuildContext context, int minutes) {
  final l10n = context.l10n;
  return switch (minutes) {
    60 => l10n.desktopFilterPauseOneHour,
    480 => l10n.desktopFilterPauseEightHours,
    _ => l10n.desktopFilterPauseMinutesOnly(minutes),
  };
}

class FilterPauseCard extends ConsumerStatefulWidget {
  const FilterPauseCard({super.key});

  @override
  ConsumerState<FilterPauseCard> createState() => _FilterPauseCardState();
}

class _FilterPauseCardState extends ConsumerState<FilterPauseCard> {
  int _minutes = 30;

  Future<void> _set(bool paused) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopFilterPauseProvider.notifier)
        .setPaused(paused, durationSec: paused ? _minutes * 60 : 0);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (paused ? l10n.desktopFilterPauseStarted : l10n.desktopFilterPauseResumed)
          : l10n.desktopFilterConfigSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopFilterPauseProvider);
    final pause = state.pause;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    return DashboardCard(
      semanticLabel: l10n.desktopFilterPauseTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.clock,
            title: l10n.desktopFilterPauseTitle,
            leading: [
              if (pause.paused)
                DashboardChip(
                  label: l10n.desktopFilterPausedChip,
                  tone: DashboardChipTone.warn,
                  dot: true,
                ),
            ],
            trailing: [
              if (state.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (state.isLoading && !pause.paused)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CommonCircleLoading(size: 20)),
            )
          else if (pause.paused)
            DashboardBlock(
              child: Row(
                spacing: 10,
                children: [
                  GlyphIcon(
                    AppGlyphs.clock,
                    size: 18,
                    color: colorScheme.warning,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          l10n.desktopFilterPauseActiveTitle,
                          style: DashboardText.rowTitle(context),
                        ),
                        Text(
                          l10n.desktopFilterPauseActiveBody(
                            desktopPauseRemaining(context, pause.remaining),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardText.label(context),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: state.saving
                        ? null
                        : () => unawaited(_set(false)),
                    icon: const GlyphIcon(AppGlyphs.arrowUp, size: 16),
                    label: Text(l10n.desktopFilterPauseResume),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Text(
                  l10n.desktopFilterPauseBody,
                  style: DashboardText.label(context),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DesktopPicker(
                      glyph: AppGlyphs.clock,
                      semanticLabel: l10n.desktopFilterPauseDuration,
                      label: _durationLabel(context, _minutes),
                      active: true,
                      items: [
                        for (final minutes in desktopPauseMinutes)
                          CommonPopupMenuItem(
                            label: _durationLabel(context, minutes),
                            checked: minutes == _minutes,
                            onPressed: () =>
                                setState(() => _minutes = minutes),
                          ),
                      ],
                    ),
                    FilledButton.tonalIcon(
                      onPressed: state.saving
                          ? null
                          : () => unawaited(_set(true)),
                      icon: const GlyphIcon(AppGlyphs.block, size: 16),
                      label: Text(l10n.desktopFilterPauseAction),
                    ),
                  ],
                ),
              ],
            ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopFilterConfigSaveFailed(state.error!.message),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(
                context,
                color: colors.warn,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
