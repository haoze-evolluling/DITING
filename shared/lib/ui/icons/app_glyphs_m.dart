// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
part of 'app_glyphs.dart';

const _g_network_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 20.8),
    GlyphVertex(12, 9.2),
  ], role: GlyphRole.line),
  GlyphCircle(12, 7.2, 1.5, role: GlyphRole.line, solid: true),
  GlyphArc(12, 7.2, 3.9, math.pi * 0.78, math.pi * 0.44, role: GlyphRole.line),
  GlyphArc(12, 7.2, 6.5, math.pi * 0.8, math.pi * 0.4, role: GlyphRole.line),
  GlyphArc(12, 7.2, 3.9, -math.pi * 0.22, math.pi * 0.44, role: GlyphRole.line),
  GlyphArc(12, 7.2, 6.5, -math.pi * 0.2, math.pi * 0.4, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(7.4, 20.8),
    GlyphVertex(16.6, 20.8),
  ], role: GlyphRole.line),
]);

const _g_pause_ = Glyph([
  GlyphBox(7.8, 4.2, 10.8, 19.8, 1.5),
  GlyphBox(13.2, 4.2, 16.2, 19.8, 1.5),
]);

const _g_shield_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 2.9, 1.5),
    GlyphVertex(19.6, 5.5, 2),
    GlyphVertex(19.6, 12.5, 5),
    GlyphVertex(12, 21.1, 2.5),
    GlyphVertex(4.4, 12.5, 5),
    GlyphVertex(4.4, 5.5, 2),
  ], closed: true),
]);

const _g_mirror_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 2.6),
    GlyphVertex(12, 21.4),
  ], role: GlyphRole.line),
  GlyphPath('M9.2 6.8 L4.2 12 L9.2 17.2 Z', role: GlyphRole.line, solid: true),
  GlyphPolyline([
    GlyphVertex(14.8, 6.8),
    GlyphVertex(19.8, 12, 0.6),
    GlyphVertex(14.8, 17.2),
  ], closed: true),
]);

const _g_folder_ = Glyph([
  GlyphPath(
    'M3.2 6.6 A2.4 2.4 0 0 1 5.6 4.2 H9.3 Q10 4.2 10.5 4.7 L12.2 6.6 '
    'H18.4 A2.4 2.4 0 0 1 20.8 9 V17.4 A2.4 2.4 0 0 1 18.4 19.8 '
    'H5.6 A2.4 2.4 0 0 1 3.2 17.4 Z',
  ),
]);

const _g_resize_ = Glyph([
  GlyphPolyline([
    GlyphVertex(13.8, 10.2),
    GlyphVertex(19.6, 4.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(15.2, 4.4),
    GlyphVertex(19.6, 4.4, 0.6),
    GlyphVertex(19.6, 8.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(10.2, 13.8),
    GlyphVertex(4.4, 19.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(8.8, 19.6),
    GlyphVertex(4.4, 19.6, 0.6),
    GlyphVertex(4.4, 15.2),
  ], role: GlyphRole.line),
]);

const _g_calendar_ = Glyph([
  GlyphBox(3, 5.2, 21, 20.8, 2.6),
  GlyphPolyline([
    GlyphVertex(7.6, 2.8),
    GlyphVertex(7.6, 5.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(16.4, 2.8),
    GlyphVertex(16.4, 5.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(3, 9.8),
    GlyphVertex(21, 9.8),
  ], role: GlyphRole.detail),
  GlyphCircle(7.8, 13.6, 1.05, role: GlyphRole.detail, solid: true),
  GlyphCircle(12, 13.6, 1.05, role: GlyphRole.detail, solid: true),
  GlyphCircle(16.2, 13.6, 1.05, role: GlyphRole.detail, solid: true),
  GlyphCircle(7.8, 17.2, 1.05, role: GlyphRole.detail, solid: true),
  GlyphCircle(12, 17.2, 1.05, role: GlyphRole.detail, solid: true),
  GlyphCircle(16.2, 17.2, 1.05, role: GlyphRole.detail, solid: true),
]);

const _g_stethoscope_ = Glyph([
  GlyphPath('M7.4 3.6 V9 A4.6 4.6 0 0 0 16.6 9 V3.6', role: GlyphRole.line),
  GlyphCircle(7.4, 3.2, 1.2, role: GlyphRole.line, solid: true),
  GlyphCircle(16.6, 3.2, 1.2, role: GlyphRole.line, solid: true),
  GlyphPolyline([
    GlyphVertex(12, 13.6),
    GlyphVertex(12, 16.4),
  ], role: GlyphRole.line),
  GlyphCircle(12, 18.6, 2.2),
  GlyphCircle(12, 18.6, 1, role: GlyphRole.detail, solid: true),
]);

const _g_upstream_ = Glyph([
  GlyphPath(
    'M7 19.4A4.2 4.2 0 0 1 5.06 11.47A6 6 0 1 1 16.95 9.83A4.8 4.8 0 0 1 16.4 19.4Z',
  ),
  GlyphPolyline([
    GlyphVertex(12, 16),
    GlyphVertex(12, 8.4),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(9, 11.4),
    GlyphVertex(12, 8.4, 0.4),
    GlyphVertex(15, 11.4),
  ], role: GlyphRole.detail),
]);

const _g_record_ = Glyph([
  GlyphCircle(12, 12, 8.8),
  GlyphCircle(12, 12, 3.8, role: GlyphRole.detail, solid: true),
]);
