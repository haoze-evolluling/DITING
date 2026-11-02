// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:async' show Timer, scheduleMicrotask, unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui show Image;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:diting_shared/ui/color.dart';
import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:diting_shared/ui/metrics.dart';
import 'package:diting_shared/ui/motion.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/surface.dart';
import 'package:diting_shared/ui/typography.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';

import 'goo.dart';
import 'liquid_glass.dart';
import 'navigation_dock.dart' show ElasticPress, ElasticPressHandle;
import 'text.dart';
part 'popup_a.dart';
part 'popup_b.dart';
part 'popup_i.dart';
part 'popup_c.dart';
part 'popup_d.dart';
part 'popup_e.dart';
part 'popup_f.dart';
part 'popup_g.dart';
part 'popup_ext.dart';

typedef PopupAnchorResolver = Rect? Function();

typedef PopupOpen = void Function();

enum PopupPlacement { overAnchorEnd, overAnchorStart, belowPoint }

const _screenMargin = 16.0;

const _anchorOverlap = 8.0;

const _avoidGap = 8.0;

const _cardInset = 8.0;

const _itemRadius = AppCorner.md;

const _cardRadius = _itemRadius + _cardInset;

const _itemIconSize = 20.0;
const _submenuArrowSize = 16.0;

const _itemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 12);

const _itemArrowPadding = EdgeInsets.only(
  left: 12,
  top: 12,
  bottom: 12,
  right: 8,
);

/// Row metrics of [CommonPopupMenu.dense], for menus in tight spaces such as an overlay window.
const _denseItemIconSize = 18.0;
const _denseItemPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
const _denseItemArrowPadding = EdgeInsets.only(
  left: 10,
  top: 8,
  bottom: 8,
  right: 6,
);
const _denseMenuMinWidth = 140.0;
const _denseMenuMaxWidth = 240.0;

const _dividerHeight = _cardInset * 2 + 1;
