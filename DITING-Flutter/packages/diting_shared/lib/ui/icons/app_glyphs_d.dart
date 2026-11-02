// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'app_glyphs.dart';

const _g_send_ = Glyph([
  GlyphPolyline([
    GlyphVertex(3.2, 10.8, 1),
    GlyphVertex(20.6, 3.4, 1),
    GlyphVertex(13.2, 20.8, 1),
    GlyphVertex(10.6, 13.4, 0.6),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(10.6, 13.4),
    GlyphVertex(15.2, 8.8),
  ], role: GlyphRole.detail),
]);

const _g_rules_ = Glyph([
  GlyphBox(3, 4, 21, 20, 3),
  GlyphCircle(7, 8, 1.1, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(10.8, 8),
    GlyphVertex(17.2, 8),
  ], role: GlyphRole.detail),
  GlyphCircle(7, 12, 1.1, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(10.8, 12),
    GlyphVertex(17.2, 12),
  ], role: GlyphRole.detail),
  GlyphCircle(7, 16, 1.1, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(10.8, 16),
    GlyphVertex(17.2, 16),
  ], role: GlyphRole.detail),
], matchTextDirection: true);

const _g_rulePresets_ = Glyph([
  GlyphBox(3, 9.5, 21, 21, 3),
  GlyphPolyline([
    GlyphVertex(5.5, 6.2),
    GlyphVertex(18.5, 6.2),
  ], role: GlyphRole.line),
  GlyphPolyline([GlyphVertex(8, 3), GlyphVertex(16, 3)], role: GlyphRole.line),
  GlyphCircle(7, 13.4, 1.1, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(10.8, 13.4),
    GlyphVertex(17.2, 13.4),
  ], role: GlyphRole.detail),
  GlyphCircle(7, 17.1, 1.1, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(10.8, 17.1),
    GlyphVertex(17.2, 17.1),
  ], role: GlyphRole.detail),
], matchTextDirection: true);

const _g_code_ = Glyph([
  GlyphPolyline([
    GlyphVertex(7.5, 7.5),
    GlyphVertex(3, 12, 0.5),
    GlyphVertex(7.5, 16.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(16.5, 7.5),
    GlyphVertex(21, 12, 0.5),
    GlyphVertex(16.5, 16.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(13.8, 5),
    GlyphVertex(10.2, 19),
  ], role: GlyphRole.line),
]);

const _g_settings_ = Glyph([
  GlyphPolyline([
    GlyphVertex(9.87, 5.44, 0.6),
    GlyphVertex(10.09, 3, 0.9),
    GlyphVertex(13.91, 3, 0.9),
    GlyphVertex(14.13, 5.44, 0.6),
    GlyphVertex(16.62, 6.87, 0.6),
    GlyphVertex(18.84, 5.84, 0.9),
    GlyphVertex(20.75, 9.16, 0.9),
    GlyphVertex(18.75, 10.57, 0.6),
    GlyphVertex(18.75, 13.43, 0.6),
    GlyphVertex(20.75, 14.84, 0.9),
    GlyphVertex(18.84, 18.16, 0.9),
    GlyphVertex(16.62, 17.13, 0.6),
    GlyphVertex(14.13, 18.56, 0.6),
    GlyphVertex(13.91, 21, 0.9),
    GlyphVertex(10.09, 21, 0.9),
    GlyphVertex(9.87, 18.56, 0.6),
    GlyphVertex(7.38, 17.13, 0.6),
    GlyphVertex(5.16, 18.16, 0.9),
    GlyphVertex(3.25, 14.84, 0.9),
    GlyphVertex(5.25, 13.43, 0.6),
    GlyphVertex(5.25, 10.57, 0.6),
    GlyphVertex(3.25, 9.16, 0.9),
    GlyphVertex(5.16, 5.84, 0.9),
    GlyphVertex(7.38, 6.87, 0.6),
  ], closed: true),
  GlyphCircle(12, 12, 3, role: GlyphRole.detail),
]);

const _g_sliders_ = Glyph([
  GlyphPolyline([
    GlyphVertex(3.2, 5.5),
    GlyphVertex(10.4, 5.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.6, 5.5),
    GlyphVertex(20.8, 5.5),
  ], role: GlyphRole.line),
  GlyphCircle(14.5, 5.5, 2.5),
  GlyphPolyline([
    GlyphVertex(3.2, 12),
    GlyphVertex(4.4, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12.6, 12),
    GlyphVertex(20.8, 12),
  ], role: GlyphRole.line),
  GlyphCircle(8.5, 12, 2.5),
  GlyphPolyline([
    GlyphVertex(3.2, 18.5),
    GlyphVertex(11.4, 18.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(19.6, 18.5),
    GlyphVertex(20.8, 18.5),
  ], role: GlyphRole.line),
  GlyphCircle(15.5, 18.5, 2.5),
]);

const _g_wrench_ = Glyph([
  GlyphPath(
    'M3.58 17.59L10.1 11.07A1.2 1.2 0 0 0 10.41 9.89'
    'A5.4 5.4 0 0 1 16.36 3.05A0.9 0.9 0 0 1 16.87 4.58L14.04 7.41'
    'A1.8 1.8 0 0 0 16.59 9.96L19.42 7.13A0.9 0.9 0 0 1 20.95 7.64'
    'A5.4 5.4 0 0 1 14.11 13.59A1.2 1.2 0 0 0 12.93 13.9L6.41 20.42'
    'A2 2 0 0 1 3.58 17.59Z',
  ),
]);

const _g_toggle_ = Glyph([
  GlyphBox(2.9, 6.5, 21.1, 17.5, 5.5),
  GlyphCircle(8.4, 12, 2.8, role: GlyphRole.detail, solid: true),
]);

const _g_pin_ = Glyph([
  GlyphPolyline([
    GlyphVertex(15.42, 3.5, 1.5),
    GlyphVertex(20.5, 8.58, 1.5),
    GlyphVertex(15.73, 13.35, 1.4),
    GlyphVertex(14.94, 19.55, 1),
    GlyphVertex(4.45, 9.06, 1),
    GlyphVertex(10.65, 8.27, 1.4),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(9.7, 14.3),
    GlyphVertex(3.5, 20.5),
  ], role: GlyphRole.line),
]);

const _g_eye_ = Glyph([
  GlyphPath(
    'M3.01 11.32A10.08 10.08 0 0 1 20.99 11.32A1.5 1.5 0 0 1 20.99 12.68'
    'A10.08 10.08 0 0 1 3.01 12.68A1.5 1.5 0 0 1 3.01 11.32Z',
  ),
  GlyphCircle(12, 12, 2.8, role: GlyphRole.detail),
]);

const _g_eyeOff_ = Glyph([
  GlyphPath(
    'M10.95 5.86A10.08 10.08 0 0 1 20.99 11.32A1.5 1.5 0 0 1 20.99 12.68'
    'A10.08 10.08 0 0 1 19.71 14.62',
    role: GlyphRole.line,
  ),
  GlyphPath(
    'M16.92 16.92A10.08 10.08 0 0 1 3.01 12.68A1.5 1.5 0 0 1 3.01 11.32'
    'A10.08 10.08 0 0 1 7.08 7.08',
    role: GlyphRole.line,
  ),
  GlyphArc(12, 12, 2.8, math.pi * 0.25, math.pi, role: GlyphRole.line),
  GlyphPolyline([GlyphVertex(4, 4), GlyphVertex(20, 20)], role: GlyphRole.line),
]);

const _g_lock_ = Glyph([
  GlyphBox(5, 10.5, 19, 20.8, 2.5),
  GlyphPath('M8.5 10.5V7A3.5 3.5 0 0 1 15.5 7V10.5', role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 14.4),
    GlyphVertex(12, 17),
  ], role: GlyphRole.detail),
]);

const _g_lockOpen_ = Glyph([
  GlyphBox(5, 10.5, 19, 20.8, 2.5),
  GlyphPath('M8.5 10.5V7A3.5 3.5 0 0 1 15.5 7', role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 14.4),
    GlyphVertex(12, 17),
  ], role: GlyphRole.detail),
]);

const _g_key_ = Glyph([
  GlyphCircle(9.27, 7.99, 5),
  GlyphCircle(9.27, 7.99, 1.4, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(12.8, 11.53),
    GlyphVertex(19.73, 18.46, 0.8),
    GlyphVertex(17.19, 21.01),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17.19, 15.91),
    GlyphVertex(15.07, 18.04),
  ], role: GlyphRole.line),
]);

const _g_password_ = Glyph([
  GlyphBox(2.9, 6, 21.1, 18, 3),
  GlyphCircle(7.4, 12, 1.4, role: GlyphRole.detail, solid: true),
  GlyphCircle(12, 12, 1.4, role: GlyphRole.detail, solid: true),
  GlyphCircle(16.6, 12, 1.4, role: GlyphRole.detail, solid: true),
]);

const _g_account_ = Glyph([
  GlyphCircle(12, 12, 8.8),
  GlyphCircle(12, 9.4, 2.8, role: GlyphRole.detail),
  GlyphArc(
    12,
    22.6,
    7,
    math.pi * -0.8087,
    math.pi * 0.6173,
    role: GlyphRole.detail,
  ),
]);

const _g_sparkle_ = Glyph([
  GlyphPolyline([
    GlyphVertex(10, 6.4, 0.9),
    GlyphVertex(11.48, 12.32, 3),
    GlyphVertex(17.4, 13.8, 0.9),
    GlyphVertex(11.48, 15.28, 3),
    GlyphVertex(10, 21.2, 0.9),
    GlyphVertex(8.52, 15.28, 3),
    GlyphVertex(2.6, 13.8, 0.9),
    GlyphVertex(8.52, 12.32, 3),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(17.8, 2.9, 0.6),
    GlyphVertex(18.58, 5.42, 1.2),
    GlyphVertex(21.1, 6.2, 0.6),
    GlyphVertex(18.58, 6.98, 1.2),
    GlyphVertex(17.8, 9.5, 0.6),
    GlyphVertex(17.02, 6.98, 1.2),
    GlyphVertex(14.5, 6.2, 0.6),
    GlyphVertex(17.02, 5.42, 1.2),
  ], closed: true),
]);

const _g_bolt_ = Glyph([
  GlyphPolyline([
    GlyphVertex(14.5, 2.8, 1),
    GlyphVertex(5, 13.7, 1),
    GlyphVertex(11.2, 13.7, 0.6),
    GlyphVertex(9.5, 21.2, 1),
    GlyphVertex(19, 10.3, 1),
    GlyphVertex(12.8, 10.3, 0.6),
  ], closed: true),
]);

const _g_locate_ = Glyph([
  GlyphCircle(12, 12, 6.2),
  GlyphCircle(12, 12, 1.8, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(12, 2.9),
    GlyphVertex(12, 5.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 18.2),
    GlyphVertex(12, 21.1),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(2.9, 12),
    GlyphVertex(5.8, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.2, 12),
    GlyphVertex(21.1, 12),
  ], role: GlyphRole.line),
]);

const _g_star_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 3.2, 1.2),
    GlyphVertex(14.41, 9.48, 0.6),
    GlyphVertex(21.13, 9.83, 1.2),
    GlyphVertex(15.9, 14.07, 0.6),
    GlyphVertex(17.64, 20.57, 1.2),
    GlyphVertex(12, 16.9, 0.6),
    GlyphVertex(6.36, 20.57, 1.2),
    GlyphVertex(8.1, 14.07, 0.6),
    GlyphVertex(2.87, 9.83, 1.2),
    GlyphVertex(9.59, 9.48, 0.6),
  ], closed: true),
]);

const _g_puzzle_ = Glyph([
  GlyphPath(
    'M3 10A2.2 2.2 0 0 1 5.2 7.8H7.94A2.6 2.6 0 1 1 11.26 7.8H14'
    'A2.2 2.2 0 0 1 16.2 10V12.74A2.6 2.6 0 1 1 16.2 16.06V18.8'
    'A2.2 2.2 0 0 1 14 21H5.2A2.2 2.2 0 0 1 3 18.8V17.58'
    'A0.8 0.8 0 0 1 4.08 16.83A2.6 2.6 0 1 0 4.08 11.97'
    'A0.8 0.8 0 0 1 3 11.22Z',
  ),
]);

const _g_customize_ = Glyph([
  GlyphBox(3.5, 3.5, 10.5, 10.5, 2),
  GlyphBox(3.5, 13.5, 10.5, 20.5, 2),
  GlyphBox(13.5, 13.5, 20.5, 20.5, 2),
  GlyphPolyline([
    GlyphVertex(17, 4),
    GlyphVertex(17, 10),
  ], role: GlyphRole.line),
  GlyphPolyline([GlyphVertex(14, 7), GlyphVertex(20, 7)], role: GlyphRole.line),
]);

const _g_layers_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 3, 1.5),
    GlyphVertex(20.8, 7.6, 1.2),
    GlyphVertex(12, 12.2, 1.5),
    GlyphVertex(3.2, 7.6, 1.2),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(3.2, 12),
    GlyphVertex(12, 16.6, 1.5),
    GlyphVertex(20.8, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(3.2, 16.4),
    GlyphVertex(12, 21, 1.5),
    GlyphVertex(20.8, 16.4),
  ], role: GlyphRole.line),
]);

const _g_sun_ = Glyph([
  GlyphCircle(12, 12, 4),
  GlyphPolyline([
    GlyphVertex(12, 2.9),
    GlyphVertex(12, 4.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 19.6),
    GlyphVertex(12, 21.1),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(2.9, 12),
    GlyphVertex(4.4, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(19.6, 12),
    GlyphVertex(21.1, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.57, 5.57),
    GlyphVertex(6.63, 6.63),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.43, 5.57),
    GlyphVertex(17.37, 6.63),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.57, 18.43),
    GlyphVertex(6.63, 17.37),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.43, 18.43),
    GlyphVertex(17.37, 17.37),
  ], role: GlyphRole.line),
]);

const _g_pureBlack_ = Glyph([
  GlyphBox(3, 3.5, 21, 16.5, 2.5),
  GlyphPath(
    'M7 6H17A1.5 1.5 0 0 1 18.5 7.5V12.5A1.5 1.5 0 0 1 17 14H7A1.5 1.5 0 0 1 5.5 12.5V7.5A1.5 1.5 0 0 1 7 6Z',
    role: GlyphRole.detail,
    solid: true,
  ),
  GlyphPolyline([
    GlyphVertex(12, 16.5),
    GlyphVertex(12, 20.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(8, 20.4),
    GlyphVertex(16, 20.4),
  ], role: GlyphRole.line),
]);

const _g_palette_ = Glyph([
  GlyphPath(
    'M20.59 13.9A8.8 8.8 0 1 0 13.9 20.59A1.2 1.2 0 0 0 14.83 19.28A4 4 0 0 1 19.28 14.83A1.2 1.2 0 0 0 20.59 13.9Z',
  ),
  GlyphCircle(7.54, 13.89, 1.4, role: GlyphRole.detail, solid: true),
  GlyphCircle(7.96, 9.32, 1.4, role: GlyphRole.detail, solid: true),
  GlyphCircle(12, 7.15, 1.4, role: GlyphRole.detail, solid: true),
  GlyphCircle(16.04, 9.32, 1.4, role: GlyphRole.detail, solid: true),
]);

const _g_paintbrush_ = Glyph([
  GlyphPolyline([
    GlyphVertex(9.1, 10.51, 1.2),
    GlyphVertex(13.49, 14.9, 1.2),
    GlyphVertex(9.95, 18.43, 3.6),
    GlyphVertex(4.08, 20.2, 1),
    GlyphVertex(5.57, 14.05, 3.6),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(12.64, 8.96, 0.6),
    GlyphVertex(15.04, 11.36, 0.6),
    GlyphVertex(21.4, 5, 1.7),
    GlyphVertex(19, 2.6, 1.7),
  ], closed: true),
]);

const _g_eyedropper_ = Glyph([
  GlyphPolyline([
    GlyphVertex(4.79, 19.21, 0.9),
    GlyphVertex(8.46, 18.08, 1.2),
    GlyphVertex(14.4, 12.14, 0.5),
    GlyphVertex(16.24, 13.98, 1),
    GlyphVertex(18.79, 11.43, 1),
    GlyphVertex(17.73, 10.37, 0.5),
    GlyphVertex(21.4, 6.7, 2.9),
    GlyphVertex(17.3, 2.6, 2.9),
    GlyphVertex(13.63, 6.27, 0.5),
    GlyphVertex(12.57, 5.21, 1),
    GlyphVertex(10.02, 7.76, 1),
    GlyphVertex(11.86, 9.6, 0.5),
    GlyphVertex(5.92, 15.54, 1.2),
  ], closed: true),
]);

const _g_motion_ = Glyph([
  GlyphCircle(15.6, 12, 5.3),
  GlyphPolyline([
    GlyphVertex(4.4, 8),
    GlyphVertex(7.6, 8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(2.9, 12),
    GlyphVertex(6.5, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4.4, 16),
    GlyphVertex(7.6, 16),
  ], role: GlyphRole.line),
]);
