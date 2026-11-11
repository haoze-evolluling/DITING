// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'app_glyphs.dart';

const _g_error_ = Glyph([
  GlyphCircle(12, 12, 8.8),
  GlyphPolyline([
    GlyphVertex(12, 7.3),
    GlyphVertex(12, 12.2),
  ], role: GlyphRole.detail),
  GlyphCircle(12, 16.5, 1.4, role: GlyphRole.detail, solid: true),
]);

const _g_more_ = Glyph([
  GlyphCircle(12, 5.5, 1.4, role: GlyphRole.line, solid: true),
  GlyphCircle(12, 12, 1.4, role: GlyphRole.line, solid: true),
  GlyphCircle(12, 18.5, 1.4, role: GlyphRole.line, solid: true),
]);

const _g_moreCircle_ = Glyph([
  GlyphCircle(12, 12, 8.8),
  GlyphCircle(7.4, 12, 1.4, role: GlyphRole.detail, solid: true),
  GlyphCircle(12, 12, 1.4, role: GlyphRole.detail, solid: true),
  GlyphCircle(16.6, 12, 1.4, role: GlyphRole.detail, solid: true),
]);

const _g_dragHandle_ = Glyph([
  GlyphPolyline([GlyphVertex(4, 7), GlyphVertex(20, 7)], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4, 12),
    GlyphVertex(20, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4, 17),
    GlyphVertex(20, 17),
  ], role: GlyphRole.line),
]);

const _g_sort_ = Glyph([
  GlyphPolyline([GlyphVertex(4, 7), GlyphVertex(20, 7)], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4, 12),
    GlyphVertex(15, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4, 17),
    GlyphVertex(10, 17),
  ], role: GlyphRole.line),
], matchTextDirection: true);

const _g_filter_ = Glyph([
  GlyphPolyline([GlyphVertex(4, 7), GlyphVertex(20, 7)], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(7, 12),
    GlyphVertex(17, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(10, 17),
    GlyphVertex(14, 17),
  ], role: GlyphRole.line),
]);

const _g_textShort_ = Glyph([
  GlyphPolyline([GlyphVertex(4, 9), GlyphVertex(20, 9)], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4, 15),
    GlyphVertex(13, 15),
  ], role: GlyphRole.line),
], matchTextDirection: true);

const _g_wrap_ = Glyph([
  GlyphPolyline([GlyphVertex(4, 6), GlyphVertex(20, 6)], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4, 12),
    GlyphVertex(20, 12, 3),
    GlyphVertex(20, 18, 3),
    GlyphVertex(11, 18),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(13.8, 15.2),
    GlyphVertex(11, 18, 0.4),
    GlyphVertex(13.8, 20.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4, 18),
    GlyphVertex(6.5, 18),
  ], role: GlyphRole.line),
], matchTextDirection: true);

const _g_listAdd_ = Glyph([
  GlyphPolyline([
    GlyphVertex(4, 4.4),
    GlyphVertex(20, 4.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4, 9.2),
    GlyphVertex(20, 9.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4, 14),
    GlyphVertex(10, 14),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17, 13.4),
    GlyphVertex(17, 20.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(13.6, 16.8),
    GlyphVertex(20.4, 16.8),
  ], role: GlyphRole.line),
], matchTextDirection: true);

const _g_edit_ = Glyph([
  GlyphPolyline([
    GlyphVertex(4, 20, 1),
    GlyphVertex(8.75, 18.75, 1),
    GlyphVertex(20.25, 7.25, 1.5),
    GlyphVertex(16.75, 3.75, 1.5),
    GlyphVertex(5.25, 15.25, 1),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(13.25, 7.25),
    GlyphVertex(16.75, 10.75),
  ], role: GlyphRole.detail),
]);

const _g_compose_ = Glyph([
  GlyphPolyline([
    GlyphVertex(9.4, 6.2),
    GlyphVertex(4, 6.2, 2.5),
    GlyphVertex(4, 20.2, 2.5),
    GlyphVertex(18, 20.2, 2.5),
    GlyphVertex(18, 14.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(9, 15.2, 1),
    GlyphVertex(13.75, 13.95, 1),
    GlyphVertex(20.75, 6.95, 1.5),
    GlyphVertex(17.25, 3.45, 1.5),
    GlyphVertex(10.25, 10.45, 1),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(13.75, 6.95),
    GlyphVertex(17.25, 10.45),
  ], role: GlyphRole.detail),
]);

const _g_delete_ = Glyph([
  GlyphPolyline([
    GlyphVertex(5.8, 6.8),
    GlyphVertex(18.2, 6.8),
    GlyphVertex(17.2, 21, 2.5),
    GlyphVertex(6.8, 21, 2.5),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(10, 10.5),
    GlyphVertex(10, 17.5),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(14, 10.5),
    GlyphVertex(14, 17.5),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(3.8, 6.8),
    GlyphVertex(20.2, 6.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(9, 6.8),
    GlyphVertex(9, 3.2, 1.4),
    GlyphVertex(15, 3.2, 1.4),
    GlyphVertex(15, 6.8),
  ], role: GlyphRole.line),
]);

const _g_clearAll_ = Glyph([
  GlyphPolyline([
    GlyphVertex(4.24, 8.6),
    GlyphVertex(13.16, 8.6),
    GlyphVertex(12.44, 18.8, 1.8),
    GlyphVertex(4.96, 18.8, 1.8),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(8.7, 12),
    GlyphVertex(8.7, 15.3),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(3, 8.6),
    GlyphVertex(14.4, 8.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(6.2, 8.6),
    GlyphVertex(6.2, 5, 1.4),
    GlyphVertex(11.2, 5, 1.4),
    GlyphVertex(11.2, 8.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17, 11.2),
    GlyphVertex(21, 11.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17, 14.9),
    GlyphVertex(20.4, 14.9),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(17, 18.6),
    GlyphVertex(19.8, 18.6),
  ], role: GlyphRole.line),
]);

const _g_copy_ = Glyph([
  GlyphBox(8.5, 7.5, 20.5, 21, 2.5),
  GlyphPolyline([
    GlyphVertex(4, 16.5),
    GlyphVertex(4, 3, 2.5),
    GlyphVertex(16, 3),
  ], role: GlyphRole.line),
]);

const _g_cut_ = Glyph([
  GlyphCircle(7, 17.5, 3),
  GlyphCircle(17, 17.5, 3),
  GlyphPolyline([
    GlyphVertex(9.64, 13.73),
    GlyphVertex(16.8, 3.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(14.36, 13.73),
    GlyphVertex(7.2, 3.5),
  ], role: GlyphRole.line),
]);

const _g_paste_ = Glyph([
  GlyphPolyline([
    GlyphVertex(4.5, 5.2, 2.5),
    GlyphVertex(8.5, 5.2),
    GlyphVertex(8.5, 2.9, 1),
    GlyphVertex(15.5, 2.9, 1),
    GlyphVertex(15.5, 5.2),
    GlyphVertex(19.5, 5.2, 2.5),
    GlyphVertex(19.5, 21, 2.5),
    GlyphVertex(4.5, 21, 2.5),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(8.5, 5.2),
    GlyphVertex(8.5, 7.3, 1),
    GlyphVertex(15.5, 7.3, 1),
    GlyphVertex(15.5, 5.2),
  ], role: GlyphRole.detail),
]);

const _g_selectAll_ = Glyph([
  GlyphPolyline([
    GlyphVertex(3.5, 7),
    GlyphVertex(3.5, 3.5, 2.5),
    GlyphVertex(7, 3.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(20.5, 7),
    GlyphVertex(20.5, 3.5, 2.5),
    GlyphVertex(17, 3.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(20.5, 17),
    GlyphVertex(20.5, 20.5, 2.5),
    GlyphVertex(17, 20.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(3.5, 17),
    GlyphVertex(3.5, 20.5, 2.5),
    GlyphVertex(7, 20.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(10.6, 3.5),
    GlyphVertex(13.4, 3.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(20.5, 10.6),
    GlyphVertex(20.5, 13.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(13.4, 20.5),
    GlyphVertex(10.6, 20.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(3.5, 13.4),
    GlyphVertex(3.5, 10.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(8, 12.3),
    GlyphVertex(10.8, 15.1, 0.4),
    GlyphVertex(16, 9.2),
  ], role: GlyphRole.line),
]);

const _g_deselect_ = Glyph([
  GlyphPolyline([
    GlyphVertex(3.5, 7),
    GlyphVertex(3.5, 3.5, 2.5),
    GlyphVertex(7, 3.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(20.5, 7),
    GlyphVertex(20.5, 3.5, 2.5),
    GlyphVertex(17, 3.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(20.5, 17),
    GlyphVertex(20.5, 20.5, 2.5),
    GlyphVertex(17, 20.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(3.5, 17),
    GlyphVertex(3.5, 20.5, 2.5),
    GlyphVertex(7, 20.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(10.6, 3.5),
    GlyphVertex(13.4, 3.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(20.5, 10.6),
    GlyphVertex(20.5, 13.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(13.4, 20.5),
    GlyphVertex(10.6, 20.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(3.5, 13.4),
    GlyphVertex(3.5, 10.6),
  ], role: GlyphRole.line),
  GlyphPolyline([GlyphVertex(8, 8), GlyphVertex(16, 16)], role: GlyphRole.line),
]);

const _g_search_ = Glyph([
  GlyphCircle(10.3, 10.3, 6.9, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(15.18, 15.18),
    GlyphVertex(20.6, 20.6),
  ], role: GlyphRole.line),
]);

const _g_matchCase_ = Glyph([
  GlyphPolyline([
    GlyphVertex(2.4, 18.5),
    GlyphVertex(7.4, 5.5, 0.6),
    GlyphVertex(12.4, 18.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(4.13, 14),
    GlyphVertex(10.67, 14),
  ], role: GlyphRole.line),
  GlyphCircle(18.1, 15.1, 3.4, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(21.5, 11.7),
    GlyphVertex(21.5, 18.5),
  ], role: GlyphRole.line),
]);

const _g_regex_ = Glyph([
  GlyphCircle(5.5, 17.5, 0.9, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(15.5, 4),
    GlyphVertex(15.5, 13),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(11.6, 6.25),
    GlyphVertex(19.4, 10.75),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(11.6, 10.75),
    GlyphVertex(19.4, 6.25),
  ], role: GlyphRole.line),
]);

const _g_importFile_ = Glyph([
  GlyphPolyline([
    GlyphVertex(5, 3, 2.5),
    GlyphVertex(13.5, 3, 1),
    GlyphVertex(19, 8.5, 1),
    GlyphVertex(19, 21, 2.5),
    GlyphVertex(5, 21, 2.5),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(13.5, 3.2),
    GlyphVertex(13.5, 8.5, 1.5),
    GlyphVertex(18.8, 8.5),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(12, 17.6),
    GlyphVertex(12, 11.4),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(9, 14.4),
    GlyphVertex(12, 11.4, 0.4),
    GlyphVertex(15, 14.4),
  ], role: GlyphRole.detail),
]);

const _g_cloudDownload_ = Glyph([
  GlyphPath(
    'M7 19.4A4.2 4.2 0 0 1 5.06 11.47A6 6 0 1 1 16.95 9.83A4.8 4.8 0 0 1 16.4 19.4Z',
  ),
  GlyphPolyline([
    GlyphVertex(12, 8.4),
    GlyphVertex(12, 16),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(9, 13),
    GlyphVertex(12, 16, 0.4),
    GlyphVertex(15, 13),
  ], role: GlyphRole.detail),
]);

const _g_cloudSync_ = Glyph([
  GlyphPath(
    'M7 19.4A4.2 4.2 0 0 1 5.06 11.47A6 6 0 1 1 16.95 9.83A4.8 4.8 0 0 1 16.4 19.4Z',
  ),
  GlyphArc(
    11,
    13.2,
    3,
    math.pi * 0.1944,
    math.pi * 1.5,
    role: GlyphRole.detail,
  ),
  GlyphPolyline([
    GlyphVertex(12.72, 10.74),
    GlyphVertex(13.46, 11.26),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(13.01, 8.7),
    GlyphVertex(13.46, 11.26, 0.4),
    GlyphVertex(10.9, 11.71),
  ], role: GlyphRole.detail),
]);

const _g_link_ = Glyph([
  GlyphPath(
    'M11.01 8.46L14.55 4.93A3.2 3.2 0 0 1 19.07 9.45L15.54 12.99',
    role: GlyphRole.line,
  ),
  GlyphPath(
    'M12.99 15.54L9.45 19.07A3.2 3.2 0 0 1 4.93 14.55L8.46 11.01',
    role: GlyphRole.line,
  ),
  GlyphPolyline([
    GlyphVertex(9.17, 14.83),
    GlyphVertex(14.83, 9.17),
  ], role: GlyphRole.line),
]);
