// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:math' as math;

import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/surface.dart';
import 'package:diting_shared/ui/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show Hct;
import 'package:material_ui/material_ui.dart';

import 'liquid_glass.dart';
part 'navigation_dock_a.dart';
part 'navigation_dock_b.dart';
part 'navigation_dock_c.dart';
part 'navigation_dock_d.dart';
part 'navigation_dock_e.dart';
part 'navigation_dock_f.dart';

const double _barHeight = 62;
const double _barPadding = 4;
const double _edgeMargin = 21;
const double _shadowRoom = 8;

/// Quiet space [NavigationDock.insetOf] keeps below content, clear of the bar's shadow.
const double dockContentGap = 16;
const double _hitSlop = 8;
const double _maxItemExtent = 86;
const double _minLensWidth = 84;
const _fullWidthCount = 5;
const double _iconSize = 28;
const double _labelGap = 2;
const double _labelInset = 2;
const double _labelSize = 10;
const double _labelLeading = 14.5;
const double _minLabelSize = 9;
const double _pressGrowth = 1 / 8;
const double _maxPressGrowth = 16;
const double _lensGrowth = 8;
const double _lensMagnify = 0.16;
const double _liftSnap = 0.975;
const double _liftRelease = 0.04;
const double _hoverMagnet = 0.2;
const double _hoverParallax = 0.5;
const double _hoverAlpha = 0.08;
const double _hoverSwell = 0.4;
const double _jellySpeed = 3;
const double _jellyStretch = 0.2;
const double _jellyBrake = 25;
const double _jellySquash = 0.15;
const double _jellyAspect = 1.4;
const double _jellyRest = 3e-3;
const double _glowReach = 28;
const double _glowGrowth = 3;
const double _glowPeak = 0.06;
const double _glowWash = 0.7;
const double _overdrag = 0.35;
const double _pullLimit = 7 / 32;
const double _pullStretch = 0.5;
const _flingProjection = Duration(milliseconds: 100);
final _trackSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 120),
);
final _pressSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 311,
  ratio: 0.593,
);
final _followSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 1024,
  ratio: 0.9,
);
final _liftSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 250),
);
final _travelSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 400),
  bounce: 0.15,
);
final _jellySpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 100,
  ratio: 0.4,
);
final _settleSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 500),
  bounce: 0.32,
);
final _hoverSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 260),
  bounce: 0.18,
);
final _fadeSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 200),
);
final _glowInSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 100),
);
final _glowOutSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 500),
);

double _rubberBand(double overshoot, double limit) {
  final pull = 1 - 1 / (overshoot.abs() * 0.55 / limit + 1);
  return limit * pull * overshoot.sign;
}

double _saturate(double value) => 1 - 2 / (math.exp(2 * value) + 1);

Rect _lensRect({
  required double position,
  required double stretch,
  required double pitch,
  required double width,
  required double height,
  required double lift,
}) {
  final growth = _lensGrowth * 2 * lift;
  final lensWidth = (width + growth) * (1 + stretch);
  final lensHeight = (height + growth) * (1 - stretch * _jellyAspect);
  return Rect.fromLTWH(
    (position + 0.5) * pitch - lensWidth / 2,
    (height - lensHeight) / 2,
    lensWidth,
    lensHeight,
  );
}

/// Spaces destinations as iOS's tab bar does, overhanging by [_barPadding].
({double pitch, double lens, double inset}) _dockLayout(
  double span,
  int count,
) {
  if (count <= 1) {
    return (pitch: span - _barPadding * 2, lens: span, inset: _barPadding);
  }
  final pitch = (span - _barPadding * 2) / count;
  if (pitch + _barPadding * 2 >= _minLensWidth) {
    return (pitch: pitch, lens: pitch + _barPadding * 2, inset: _barPadding);
  }
  final lens = math.min(_minLensWidth, span);
  final closed = (span - lens) / (count - 1);
  return (pitch: closed, lens: lens, inset: (lens - closed) / 2);
}
