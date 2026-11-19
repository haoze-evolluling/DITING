// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
// Second hand-drawn batch: icons the first set borrowed from unrelated glyphs. Same 24x24 grid,
// 1.8 stroke and 3..21 safe area as the rest, so they sit beside the older marks without a seam.
part of 'app_glyphs.dart';

/// Trigger-to-action flow, for automation rules: one trigger branching into two actions.
/// Replaces the AI sparkle on an empty rule list.
const _g_automation_ = Glyph([
  GlyphBox(8.4, 3.2, 15.6, 8.2, 2),
  GlyphPolyline([
    GlyphVertex(12, 8.2),
    GlyphVertex(12, 12.2, 2),
    GlyphVertex(5.6, 12.2, 2),
    GlyphVertex(5.6, 14.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 12.2),
    GlyphVertex(18.4, 12.2, 2),
    GlyphVertex(18.4, 14.6),
  ], role: GlyphRole.line),
  GlyphBox(3, 14.6, 8.2, 20.4, 1.8),
  GlyphBox(15.8, 14.6, 21, 20.4, 1.8),
]);

/// Bell, for notification settings. `status` used to stand in for them.
const _g_notification_ = Glyph([
  GlyphPath(
    'M12 3.1 C8.7 3.1 6.7 5.6 6.7 8.9 V13 L5.1 15.7 Q4.7 16.6 5.7 16.6 '
    'H18.3 Q19.3 16.6 18.9 15.7 L17.3 13 V8.9 C17.3 5.6 15.3 3.1 12 3.1 Z',
  ),
  GlyphArc(12, 17, 2.1, math.pi * 0.2, math.pi * 0.6, role: GlyphRole.detail),
]);

/// Phone with vibration waves, for haptics. `motion` used to stand in for it.
const _g_vibrate_ = Glyph([
  GlyphBox(8.4, 3.2, 15.6, 20.8, 2.4),
  GlyphArc(8.4, 12, 3, math.pi * 0.75, math.pi * 0.5, role: GlyphRole.line),
  GlyphArc(8.4, 12, 5, math.pi * 0.78, math.pi * 0.44, role: GlyphRole.line),
  GlyphArc(15.6, 12, 3, -math.pi * 0.25, math.pi * 0.5, role: GlyphRole.line),
  GlyphArc(15.6, 12, 5, -math.pi * 0.22, math.pi * 0.44, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(10.6, 6.4),
    GlyphVertex(13.4, 6.4),
  ], role: GlyphRole.detail),
]);

/// Thermometer, for the agent's temperature parameter.
const _g_temperature_ = Glyph([
  GlyphPath(
    'M10.25 5.9 A1.75 1.75 0 0 1 13.75 5.9 V14.17 '
    'A3.5 3.5 0 1 1 10.25 14.17 Z',
  ),
  GlyphCircle(12, 17.2, 1.9, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(12, 8.4),
    GlyphVertex(12, 15.4),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(15, 8.4),
    GlyphVertex(16.8, 8.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(15, 11.6),
    GlyphVertex(16.8, 11.6),
  ], role: GlyphRole.line),
]);

/// Shield with a bolt, for automatic (dynamic) blocking. The plain shield is `verified`.
const _g_shieldBolt_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 2.9, 1.5),
    GlyphVertex(19.6, 5.5, 2),
    GlyphVertex(19.6, 12.5, 5),
    GlyphVertex(12, 21.1, 2.5),
    GlyphVertex(4.4, 12.5, 5),
    GlyphVertex(4.4, 5.5, 2),
  ], closed: true),
  GlyphPath(
    'M13 6.6 L9.3 12.5 H11.9 L11 17 L14.7 11.1 H12.1 Z',
    role: GlyphRole.detail,
    solid: true,
  ),
]);

/// Battery, for the "ignore battery optimisation" rows that borrowed `bolt`.
const _g_battery_ = Glyph([
  GlyphBox(2.6, 7.2, 18.8, 16.8, 2.4),
  GlyphPolyline([
    GlyphVertex(20.4, 10.2),
    GlyphVertex(20.4, 13.8),
  ], role: GlyphRole.line),
  GlyphPath(
    'M5.6 9.8 H9.6 A0.8 0.8 0 0 1 10.4 10.6 V13.4 A0.8 0.8 0 0 1 9.6 14.2 '
    'H5.6 A0.8 0.8 0 0 1 4.8 13.4 V10.6 A0.8 0.8 0 0 1 5.6 9.8 Z',
    role: GlyphRole.detail,
    solid: true,
  ),
]);

/// Beamed note pair, for the site-latency music category.
const _g_music_ = Glyph([
  GlyphCircle(7.6, 17.4, 2.4),
  GlyphCircle(16.8, 15.6, 2.4),
  GlyphPolyline([
    GlyphVertex(10, 17.4),
    GlyphVertex(10, 6.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(19.2, 15.6),
    GlyphVertex(19.2, 4.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(10, 6.6),
    GlyphVertex(19.2, 4.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(10, 9.6),
    GlyphVertex(19.2, 7.8),
  ], role: GlyphRole.line),
]);

/// Screen with a play mark, for the site-latency video category (`photos` was standing in).
const _g_video_ = Glyph([
  GlyphBox(2.8, 5.2, 21.2, 18.8, 3),
  GlyphPath(
    'M10.2 9.3 L15.4 12 L10.2 14.7 Z',
    role: GlyphRole.detail,
    solid: true,
  ),
]);

/// Shopping bag, for the site-latency shopping category (`star` was standing in).
const _g_shoppingBag_ = Glyph([
  GlyphBox(4.2, 8.4, 19.8, 20.8, 3),
  GlyphArc(12, 8.4, 3.4, math.pi, math.pi),
]);

/// Game controller, for the site-latency game category (`puzzle` was standing in).
const _g_gamepad_ = Glyph([
  GlyphBox(2.4, 7.6, 21.6, 17.8, 4.6),
  GlyphPolyline([
    GlyphVertex(6.6, 10.9),
    GlyphVertex(6.6, 14.5),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(4.8, 12.7),
    GlyphVertex(8.4, 12.7),
  ], role: GlyphRole.detail),
  GlyphCircle(16.2, 11.6, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(13.8, 14, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(18.6, 14, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(16.2, 16.4, 1.1, role: GlyphRole.detail, solid: true),
]);

/// Bug, for crash-log rows that borrowed the generic `wrench`.
const _g_bug_ = Glyph([
  GlyphPath(
    'M8.4 8.2 H15.6 A3.2 3.2 0 0 1 18.8 11.4 V14.2 '
    'A4.6 4.6 0 0 1 14.2 18.8 H9.8 A4.6 4.6 0 0 1 5.2 14.2 '
    'V11.4 A3.2 3.2 0 0 1 8.4 8.2 Z',
  ),
  GlyphPath('M9.2 8.2 V7 A2.8 2.8 0 0 1 14.8 7 V8.2', role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(9.7, 5.7),
    GlyphVertex(8.1, 3.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(14.3, 5.7),
    GlyphVertex(15.9, 3.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.4, 11.4),
    GlyphVertex(3, 10.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.2, 14.2),
    GlyphVertex(2.9, 14.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(6.4, 16.8),
    GlyphVertex(4.4, 19),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.6, 11.4),
    GlyphVertex(21, 10.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.8, 14.2),
    GlyphVertex(21.1, 14.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17.6, 16.8),
    GlyphVertex(19.6, 19),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 10.6),
    GlyphVertex(12, 18),
  ], role: GlyphRole.detail),
]);

/// Cylinder, for DNS/cache stores that borrowed `layers` or `memory`.
const _g_database_ = Glyph([
  GlyphOval(4, 3.6, 20, 8.8),
  GlyphPath('M4 6.2 V16.4 A8 2.6 0 0 0 20 16.4 V6.2'),
  GlyphPath('M4 11.6 A8 2.6 0 0 0 20 11.6', role: GlyphRole.line),
]);

/// Heart, for sponsor/thanks rows that borrowed `star` or `verified`.
const _g_heart_ = Glyph([
  GlyphPath(
    'M12 20.4 C10.2 18.7 3.5 14.1 3.5 9.4 C3.5 6.6 5.8 4.5 8.5 4.5 '
    'C10.2 4.5 11.4 5.3 12 6.5 C12.6 5.3 13.8 4.5 15.5 4.5 '
    'C18.2 4.5 20.5 6.6 20.5 9.4 C20.5 14.1 13.8 18.7 12 20.4 Z',
  ),
]);

/// Trophy, for the hit-ranking entry that borrowed `rules`.
const _g_trophy_ = Glyph([
  GlyphPath('M7.2 4.2 H16.8 V8.6 A4.8 4.8 0 0 1 7.2 8.6 Z'),
  GlyphArc(7.2, 7.6, 2.2, math.pi * 0.5, math.pi, role: GlyphRole.line),
  GlyphArc(16.8, 7.6, 2.2, -math.pi * 0.5, math.pi, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 13.4),
    GlyphVertex(12, 16.6),
  ], role: GlyphRole.line),
  GlyphBox(7.6, 16.6, 16.4, 20.2, 1.6),
]);

/// Rising signal bars, for the current-network profile row that repeated `wifi`.
const _g_signal_ = Glyph([
  GlyphBox(3.3, 15.4, 6.3, 20.7, 1.3),
  GlyphBox(8.1, 11.6, 11.1, 20.7, 1.3),
  GlyphBox(12.9, 7.8, 15.9, 20.7, 1.3),
  GlyphBox(17.7, 3.9, 20.7, 20.7, 1.3),
]);
