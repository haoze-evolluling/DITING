/// Theme previews shared by the Android appearance pages and the desktop appearance card.
///
/// Nine thumbnails are built from the same cached schemes: computing a full `ThemeData` per
/// thumbnail cost 30-40 ms on the first frame, so only the `ColorScheme` is derived here.
library;

import 'dart:async';

import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/appearance/mini_screen.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// The appearance pages ask for the same few schemes on every rebuild, one per thumbnail. Keys are
/// palette x brightness x pure black: a few dozen at most.
final _demoSchemes = <(Color, Brightness, bool), ColorScheme>{};

/// The scheme [buildAppTheme] would resolve, without building the rest of a `ThemeData`: nine
/// thumbnails each building a full theme cost the color page a 30 ms first frame.
ColorScheme demoColorScheme({
  required Color seed,
  required Brightness brightness,
  bool pureBlack = false,
}) => _demoSchemes[(seed, brightness, pureBlack)] ??= seededColorScheme(
  seedColor: seed,
  brightness: brightness,
).toPureBlack(pureBlack);

final _warmingSchemes = <(Color, Brightness, bool)>{};

/// Fills the cache for every palette while the app is idle, one scheme per task. Each takes about
/// 3 ms; the color page shows all nine, so computing them on its first frame cost 30-40 ms.
void warmDemoSchemes({
  required Brightness brightness,
  required bool pureBlack,
}) {
  for (final palette in AppPalette.values) {
    final key = (palette.effectiveSeed, brightness, pureBlack);
    if (_demoSchemes.containsKey(key) || !_warmingSchemes.add(key)) continue;
    unawaited(
      SchedulerBinding.instance.scheduleTask(() {
        _warmingSchemes.remove(key);
        demoColorScheme(seed: key.$1, brightness: key.$2, pureBlack: key.$3);
      }, Priority.idle),
    );
  }
}

/// Light and dark schemes for one preview, computed once so the same parameters do
/// not rebuild `ThemeData` on every row.
({ColorScheme light, ColorScheme dark}) previewSchemes({
  required Color seed,
  required bool pureBlack,
}) => (
  light: demoColorScheme(seed: seed, brightness: Brightness.light),
  dark: demoColorScheme(
    seed: seed,
    brightness: Brightness.dark,
    pureBlack: pureBlack,
  ),
);

Widget miniScreenThumb({
  required ColorScheme colorScheme,
  required bool floatingBar,
  bool liquidGlass = false,
  int selected = 0,
  int? previous,
  double progress = 1,
  TabTransition transition = TabTransition.slide,
}) => MiniScreenThumb(
  screen: MiniScreen(
    colorScheme: colorScheme,
    floatingBar: floatingBar,
    liquidGlass: liquidGlass,
    selected: selected,
    previous: previous,
    progress: progress,
    transition: transition,
  ),
);
