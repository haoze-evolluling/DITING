// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'app_glyphs.dart';

const _g_blur_ = Glyph([
  GlyphCircle(9.4, 9.4, 1.6, role: GlyphRole.line, solid: true),
  GlyphCircle(14.6, 9.4, 1.6, role: GlyphRole.line, solid: true),
  GlyphCircle(9.4, 14.6, 1.6, role: GlyphRole.line, solid: true),
  GlyphCircle(14.6, 14.6, 1.6, role: GlyphRole.line, solid: true),
  GlyphCircle(9.4, 4.2, 1.1, role: GlyphRole.line, solid: true),
  GlyphCircle(14.6, 4.2, 1.1, role: GlyphRole.line, solid: true),
  GlyphCircle(4.2, 9.4, 1.1, role: GlyphRole.line, solid: true),
  GlyphCircle(19.8, 9.4, 1.1, role: GlyphRole.line, solid: true),
  GlyphCircle(4.2, 14.6, 1.1, role: GlyphRole.line, solid: true),
  GlyphCircle(19.8, 14.6, 1.1, role: GlyphRole.line, solid: true),
  GlyphCircle(9.4, 19.8, 1.1, role: GlyphRole.line, solid: true),
  GlyphCircle(14.6, 19.8, 1.1, role: GlyphRole.line, solid: true),
]);

const _g_liquidGlass_ = Glyph([
  GlyphPath(
    'M12 3.4C14.6 6.2 18.4 10.2 18.4 14.4A6.4 6.4 0 0 1 5.6 14.4'
    'C5.6 10.2 9.4 6.2 12 3.4Z',
  ),
  GlyphArc(
    12,
    14.4,
    3.4,
    math.pi * 0.6,
    math.pi * 0.36,
    role: GlyphRole.detail,
  ),
]);

const _g_font_ = Glyph([
  GlyphPolyline([
    GlyphVertex(5.2, 19.6),
    GlyphVertex(12, 4.4, 0.6),
    GlyphVertex(18.8, 19.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(7.7, 14),
    GlyphVertex(16.3, 14),
  ], role: GlyphRole.line),
]);

const _g_textSize_ = Glyph([
  GlyphPolyline([
    GlyphVertex(3.2, 4.4),
    GlyphVertex(14, 4.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(8.6, 4.4),
    GlyphVertex(8.6, 19.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(14.8, 10.8),
    GlyphVertex(21, 10.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17.9, 10.8),
    GlyphVertex(17.9, 19.6),
  ], role: GlyphRole.line),
]);

const _g_language_ = Glyph([
  GlyphPolyline([
    GlyphVertex(3.2, 3.9, 3),
    GlyphVertex(20.8, 3.9, 3),
    GlyphVertex(20.8, 17.5, 3),
    GlyphVertex(10, 17.5, 0.8),
    GlyphVertex(6.2, 21, 0.6),
    GlyphVertex(6.2, 17.5, 0.6),
    GlyphVertex(3.2, 17.5, 3),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(8.6, 14.1),
    GlyphVertex(12, 7.3, 0.4),
    GlyphVertex(15.4, 14.1),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(9.85, 11.6),
    GlyphVertex(14.15, 11.6),
  ], role: GlyphRole.detail),
]);

const _g_keyboard_ = Glyph([
  GlyphBox(3, 4.6, 21, 19.4, 2.8),
  GlyphCircle(6.75, 8.3, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(10.25, 8.3, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(13.75, 8.3, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(17.25, 8.3, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(6.75, 11.9, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(10.25, 11.9, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(13.75, 11.9, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(17.25, 11.9, 1.1, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(8.6, 15.6),
    GlyphVertex(15.4, 15.6),
  ], role: GlyphRole.detail),
]);

const _g_photos_ = Glyph([
  GlyphBox(3, 6.4, 17.6, 21, 2.6),
  GlyphPolyline([
    GlyphVertex(6.4, 3),
    GlyphVertex(21, 3, 2.6),
    GlyphVertex(21, 17.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(3, 17.2),
    GlyphVertex(7.8, 12.4, 0.8),
    GlyphVertex(12.2, 16.8, 0.8),
    GlyphVertex(14, 15, 0.8),
    GlyphVertex(17.6, 18.6),
  ], role: GlyphRole.detail),
  GlyphCircle(13.4, 10.6, 1.4, role: GlyphRole.detail, solid: true),
]);

const _g_camera_ = Glyph([
  GlyphPolyline([
    GlyphVertex(3, 7.5, 2.6),
    GlyphVertex(8.2, 7.5, 0.6),
    GlyphVertex(9.6, 5, 0.8),
    GlyphVertex(14.4, 5, 0.8),
    GlyphVertex(15.8, 7.5, 0.6),
    GlyphVertex(21, 7.5, 2.6),
    GlyphVertex(21, 19.5, 2.6),
    GlyphVertex(3, 19.5, 2.6),
  ], closed: true),
  GlyphCircle(12, 13.4, 3.4, role: GlyphRole.detail),
]);

const _g_qrCode_ = Glyph([
  GlyphBox(3, 3, 10.2, 10.2, 2.2),
  GlyphBox(13.8, 3, 21, 10.2, 2.2),
  GlyphBox(3, 13.8, 10.2, 21, 2.2),
  GlyphPath(
    'M6.1 5.5H7.1A0.6 0.6 0 0 1 7.7 6.1V7.1A0.6 0.6 0 0 1 7.1 7.7H6.1A0.6 0.6 0 0 1 5.5 7.1V6.1A0.6 0.6 0 0 1 6.1 5.5Z',
    role: GlyphRole.detail,
    solid: true,
  ),
  GlyphPath(
    'M16.9 5.5H17.9A0.6 0.6 0 0 1 18.5 6.1V7.1A0.6 0.6 0 0 1 17.9 7.7H16.9A0.6 0.6 0 0 1 16.3 7.1V6.1A0.6 0.6 0 0 1 16.9 5.5Z',
    role: GlyphRole.detail,
    solid: true,
  ),
  GlyphPath(
    'M6.1 16.3H7.1A0.6 0.6 0 0 1 7.7 16.9V17.9A0.6 0.6 0 0 1 7.1 18.5H6.1A0.6 0.6 0 0 1 5.5 17.9V16.9A0.6 0.6 0 0 1 6.1 16.3Z',
    role: GlyphRole.detail,
    solid: true,
  ),
  GlyphPath(
    'M14.5 13.8H15.5A0.7 0.7 0 0 1 16.2 14.5V15.5A0.7 0.7 0 0 1 15.5 16.2H14.5A0.7 0.7 0 0 1 13.8 15.5V14.5A0.7 0.7 0 0 1 14.5 13.8Z',
    role: GlyphRole.line,
    solid: true,
  ),
  GlyphPath(
    'M19.3 13.8H20.3A0.7 0.7 0 0 1 21 14.5V15.5A0.7 0.7 0 0 1 20.3 16.2H19.3A0.7 0.7 0 0 1 18.6 15.5V14.5A0.7 0.7 0 0 1 19.3 13.8Z',
    role: GlyphRole.line,
    solid: true,
  ),
  GlyphPath(
    'M19.3 18.6H20.3A0.7 0.7 0 0 1 21 19.3V20.3A0.7 0.7 0 0 1 20.3 21H19.3A0.7 0.7 0 0 1 18.6 20.3V19.3A0.7 0.7 0 0 1 19.3 18.6Z',
    role: GlyphRole.line,
    solid: true,
  ),
]);

const _g_torch_ = Glyph([
  GlyphPolyline([
    GlyphVertex(2.24, 17.66, 1.8),
    GlyphVertex(6.34, 21.76, 1.8),
    GlyphVertex(12.92, 15.18, 1.2),
    GlyphVertex(15.61, 14.76, 0.8),
    GlyphVertex(16.74, 13.63, 1.2),
    GlyphVertex(10.37, 7.26, 1.2),
    GlyphVertex(9.24, 8.39, 0.8),
    GlyphVertex(8.82, 11.08, 1.2),
  ], closed: true),
  GlyphCircle(8.68, 15.32, 1.1, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(13.27, 5.64),
    GlyphVertex(15.25, 3.66),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(15.82, 8.18),
    GlyphVertex(17.8, 6.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.36, 10.73),
    GlyphVertex(20.34, 8.75),
  ], role: GlyphRole.line),
]);

const _g_torchOff_ = Glyph([
  GlyphPolyline([
    GlyphVertex(2.24, 17.66, 1.8),
    GlyphVertex(6.34, 21.76, 1.8),
    GlyphVertex(12.92, 15.18, 1.2),
    GlyphVertex(15.61, 14.76, 0.8),
    GlyphVertex(16.74, 13.63, 1.2),
    GlyphVertex(10.37, 7.26, 1.2),
    GlyphVertex(9.24, 8.39, 0.8),
    GlyphVertex(8.82, 11.08, 1.2),
  ], closed: true),
  GlyphCircle(8.68, 15.32, 1.1, role: GlyphRole.detail, solid: true),
]);

const _g_torchAuto_ = Glyph([
  GlyphPolyline([
    GlyphVertex(2.24, 17.66, 1.8),
    GlyphVertex(6.34, 21.76, 1.8),
    GlyphVertex(12.92, 15.18, 1.2),
    GlyphVertex(15.61, 14.76, 0.8),
    GlyphVertex(16.74, 13.63, 1.2),
    GlyphVertex(10.37, 7.26, 1.2),
    GlyphVertex(9.24, 8.39, 0.8),
    GlyphVertex(8.82, 11.08, 1.2),
  ], closed: true),
  GlyphCircle(8.68, 15.32, 1.1, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(16.3, 8),
    GlyphVertex(18.7, 2.9, 0.4),
    GlyphVertex(21.1, 8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17.1, 6.3),
    GlyphVertex(20.3, 6.3),
  ], role: GlyphRole.line),
]);

const _g_vpn_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 2.9, 1.5),
    GlyphVertex(19.6, 5.5, 2),
    GlyphVertex(19.6, 12.5, 5),
    GlyphVertex(12, 21.1, 2.5),
    GlyphVertex(4.4, 12.5, 5),
    GlyphVertex(4.4, 5.5, 2),
  ], closed: true),
  GlyphCircle(12, 10.2, 1.6, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(12, 11),
    GlyphVertex(12, 14.6),
  ], role: GlyphRole.detail),
]);

const _g_status_ = Glyph([
  GlyphBox(3, 4.2, 21, 19.8, 4.5),
  GlyphPolyline([
    GlyphVertex(6.4, 12.3),
    GlyphVertex(8.8, 12.3, 0.5),
    GlyphVertex(10.4, 8.2, 0.5),
    GlyphVertex(13.4, 16.4, 0.5),
    GlyphVertex(15, 12.3, 0.5),
    GlyphVertex(17.6, 12.3),
  ], role: GlyphRole.detail),
]);

const _g_verified_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 2.9, 1.5),
    GlyphVertex(19.6, 5.5, 2),
    GlyphVertex(19.6, 12.5, 5),
    GlyphVertex(12, 21.1, 2.5),
    GlyphVertex(4.4, 12.5, 5),
    GlyphVertex(4.4, 5.5, 2),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(8.7, 11.8),
    GlyphVertex(11, 14.1),
    GlyphVertex(15.3, 9.6),
  ], role: GlyphRole.detail),
]);

const _g_swap_ = Glyph([
  GlyphPolyline([
    GlyphVertex(3.5, 8),
    GlyphVertex(20.5, 8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17.5, 5),
    GlyphVertex(20.5, 8, 0.4),
    GlyphVertex(17.5, 11),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(20.5, 16),
    GlyphVertex(3.5, 16),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(6.5, 13),
    GlyphVertex(3.5, 16, 0.4),
    GlyphVertex(6.5, 19),
  ], role: GlyphRole.line),
]);

const _g_shuffle_ = Glyph([
  GlyphPolyline([
    GlyphVertex(3, 7),
    GlyphVertex(7, 7, 2),
    GlyphVertex(15, 17, 2),
    GlyphVertex(20.5, 17),
  ], role: GlyphRole.line),
  GlyphPath('M3 17H5Q7 17 8.25 15.44L8.69 14.88', role: GlyphRole.line),
  GlyphPath('M13.31 9.12L13.75 8.56Q15 7 17 7H20.5', role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17.5, 4),
    GlyphVertex(20.5, 7, 0.4),
    GlyphVertex(17.5, 10),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17.5, 14),
    GlyphVertex(20.5, 17, 0.4),
    GlyphVertex(17.5, 20),
  ], role: GlyphRole.line),
]);

const _g_split_ = Glyph([
  GlyphPolyline([
    GlyphVertex(4.5, 4),
    GlyphVertex(12, 11.5, 2.5),
    GlyphVertex(12, 20.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(19.5, 4),
    GlyphVertex(12, 11.5, 2.5),
    GlyphVertex(12, 20.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4.5, 9.5),
    GlyphVertex(4.5, 4, 0.5),
    GlyphVertex(10, 4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(14, 4),
    GlyphVertex(19.5, 4, 0.5),
    GlyphVertex(19.5, 9.5),
  ], role: GlyphRole.line),
]);

const _g_speed_ = Glyph([
  GlyphPath(
    'M6.759 19.057 Q5.259 19.057 4.396 17.83 A8.8 8.8 0 1 1 19.604 17.83 '
    'Q18.741 19.057 17.241 19.057 Z',
  ),
  GlyphCircle(12, 13.4, 1.4, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(12, 13.4),
    GlyphVertex(15.47, 9.26),
  ], role: GlyphRole.detail),
]);

const _g_dataUsage_ = Glyph([
  GlyphPath(
    'M10 14 H15.8 Q17 14 16.897 15.194 '
    'A7 7 0 1 1 8.806 7.103 Q10 7 10 8.2 Z',
  ),
  GlyphPath(
    'M13.6 9.4 V4.6 Q13.6 3.4 14.794 3.503 '
    'A7 7 0 0 1 20.497 9.206 Q20.6 10.4 19.4 10.4 '
    'H14.6 Q13.6 10.4 13.6 9.4 Z',
  ),
]);

const _g_memory_ = Glyph([
  GlyphBox(3.5, 7.2, 20.5, 16.8, 2.5),
  GlyphPolyline([
    GlyphVertex(8, 7.2),
    GlyphVertex(8, 3.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 7.2),
    GlyphVertex(12, 3.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(16, 7.2),
    GlyphVertex(16, 3.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(8, 16.8),
    GlyphVertex(8, 20.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 16.8),
    GlyphVertex(12, 20.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(16, 16.8),
    GlyphVertex(16, 20.2),
  ], role: GlyphRole.line),
]);

const _g_cpu_ = Glyph([
  GlyphBox(5.5, 5.5, 18.5, 18.5, 2.2),
  GlyphBox(9.2, 9.2, 14.8, 14.8, 1.2, role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(8.4, 5.5),
    GlyphVertex(8.4, 2.9),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 5.5),
    GlyphVertex(12, 2.9),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(15.6, 5.5),
    GlyphVertex(15.6, 2.9),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(8.4, 18.5),
    GlyphVertex(8.4, 21.1),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 18.5),
    GlyphVertex(12, 21.1),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(15.6, 18.5),
    GlyphVertex(15.6, 21.1),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.5, 8.4),
    GlyphVertex(2.9, 8.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.5, 12),
    GlyphVertex(2.9, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.5, 15.6),
    GlyphVertex(2.9, 15.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.5, 8.4),
    GlyphVertex(21.1, 8.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.5, 12),
    GlyphVertex(21.1, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(18.5, 15.6),
    GlyphVertex(21.1, 15.6),
  ], role: GlyphRole.line),
]);

const _g_devices_ = Glyph([
  GlyphPolyline([
    GlyphVertex(11.4, 14.5),
    GlyphVertex(4, 14.5, 2),
    GlyphVertex(4, 4, 2),
    GlyphVertex(18.8, 4, 2),
    GlyphVertex(18.8, 6.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(2.9, 18.2),
    GlyphVertex(11.4, 18.2),
  ], role: GlyphRole.line),
  GlyphBox(15, 10, 20.8, 20.5, 2),
]);

const _g_broom_ = Glyph([
  GlyphPolyline([
    GlyphVertex(20.1, 3.9),
    GlyphVertex(13.6, 10.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(15.44, 12.24, 1),
    GlyphVertex(11.76, 8.56, 1),
    GlyphVertex(9.78, 10.54),
    GlyphVertex(13.46, 14.22),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(14.02, 14.78, 1),
    GlyphVertex(9.22, 9.98, 1),
    GlyphVertex(3.28, 13.09, 1.5),
    GlyphVertex(10.91, 20.72, 1.5),
  ], closed: true),
]);
