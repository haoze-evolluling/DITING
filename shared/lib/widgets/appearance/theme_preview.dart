library;

import 'dart:async';

import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/appearance/mini_screen.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

final _demoSchemes = <(Color, Brightness, bool), ColorScheme>{};

ColorScheme demoColorScheme({
  required Color seed,
  required Brightness brightness,
  bool pureBlack = false,
}) => _demoSchemes[(seed, brightness, pureBlack)] ??= seededColorScheme(
  seedColor: seed,
  brightness: brightness,
).toPureBlack(pureBlack);

final _warmingSchemes = <(Color, Brightness, bool)>{};

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
