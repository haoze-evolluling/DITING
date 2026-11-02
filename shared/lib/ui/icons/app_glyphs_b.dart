// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'app_glyphs.dart';

const _g_dashboard_ = Glyph([
  GlyphBox(3.5, 3.5, 10.5, 11.5, 2),
  GlyphBox(13.5, 3.5, 20.5, 9.5, 2),
  GlyphBox(3.5, 14.5, 10.5, 20.5, 2),
  GlyphBox(13.5, 12.5, 20.5, 20.5, 2),
]);

const _g_proxies_ = Glyph([
  GlyphCircle(12, 12, 8.8),
  GlyphOval(8.2, 3.2, 15.8, 20.8, role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(3.2, 12),
    GlyphVertex(20.8, 12),
  ], role: GlyphRole.detail),
]);

const _g_profiles_ = Glyph([
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
    GlyphVertex(8.5, 12.5),
    GlyphVertex(15.5, 12.5),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(8.5, 16),
    GlyphVertex(13, 16),
  ], role: GlyphRole.detail),
]);

const _g_requests_ = Glyph([
  GlyphCircle(12, 12, 8.8),
  GlyphPolyline([
    GlyphVertex(12, 7.2),
    GlyphVertex(12, 12, 0.6),
    GlyphVertex(15.2, 14),
  ], role: GlyphRole.detail),
]);

const _g_clock_ = _g_requests_;

const _g_connections_ = Glyph([
  GlyphCircle(12, 5.2, 2.4),
  GlyphCircle(5.2, 17.6, 2.4),
  GlyphCircle(18.8, 17.6, 2.4),
  GlyphLink(Offset(12, 5.2), Offset(5.2, 17.6), 2.4),
  GlyphLink(Offset(12, 5.2), Offset(18.8, 17.6), 2.4),
  GlyphLink(Offset(5.2, 17.6), Offset(18.8, 17.6), 2.4),
]);

const _g_dns_ = Glyph([
  GlyphBox(3.5, 3.5, 20.5, 10.5, 2.5),
  GlyphBox(3.5, 13.5, 20.5, 20.5, 2.5),
  GlyphCircle(7.2, 7, 1.1, role: GlyphRole.detail, solid: true),
  GlyphCircle(7.2, 17, 1.1, role: GlyphRole.detail, solid: true),
]);

const _g_resources_ = Glyph([
  GlyphBox(3, 3.5, 21, 8.5, 1.8),
  GlyphBox(4.5, 10.8, 19.5, 20.5, 2.2),
  GlyphPolyline([
    GlyphVertex(10, 14.2),
    GlyphVertex(14, 14.2),
  ], role: GlyphRole.detail),
]);

const _g_logs_ = Glyph([
  GlyphBox(3, 4.5, 21, 19.5, 3.5),
  GlyphPolyline([
    GlyphVertex(7.3, 9.3),
    GlyphVertex(9.9, 11.9, 0.4),
    GlyphVertex(7.3, 14.5),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(12.2, 14.5),
    GlyphVertex(16.2, 14.5),
  ], role: GlyphRole.detail),
]);

const _g_tools_ = Glyph([
  GlyphBox(3, 7, 21, 20, 2.8),
  GlyphPolyline([
    GlyphVertex(9, 7),
    GlyphVertex(9, 4.6, 1.4),
    GlyphVertex(15, 4.6, 1.4),
    GlyphVertex(15, 7),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(3.2, 12.6),
    GlyphVertex(9.6, 12.6),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(14.4, 12.6),
    GlyphVertex(20.8, 12.6),
  ], role: GlyphRole.detail),
  GlyphBox(10.4, 11, 13.6, 14.4, 1, role: GlyphRole.detail),
]);

const _g_target_ = Glyph([
  GlyphArc(12, 12, 8.8, math.pi * -0.93, math.pi * 0.86, role: GlyphRole.line),
  GlyphArc(12, 12, 8.8, math.pi * 0.07, math.pi * 0.86, role: GlyphRole.line),
  GlyphCircle(12, 12, 2),
]);

const _g_arrowBack_ = Glyph([
  GlyphPolyline([
    GlyphVertex(5, 12),
    GlyphVertex(19, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(11.5, 5.5),
    GlyphVertex(5, 12, 0.4),
    GlyphVertex(11.5, 18.5),
  ], role: GlyphRole.line),
], matchTextDirection: true);

const _g_chevronBack_ = Glyph([
  GlyphPolyline([
    GlyphVertex(15.25, 5.5),
    GlyphVertex(8.75, 12, 0.4),
    GlyphVertex(15.25, 18.5),
  ], role: GlyphRole.line),
], matchTextDirection: true);

const _g_chevronForward_ = Glyph([
  GlyphPolyline([
    GlyphVertex(8.75, 5.5),
    GlyphVertex(15.25, 12, 0.4),
    GlyphVertex(8.75, 18.5),
  ], role: GlyphRole.line),
], matchTextDirection: true);

const _g_chevronDown_ = Glyph([
  GlyphPolyline([
    GlyphVertex(5.5, 8.75),
    GlyphVertex(12, 15.25, 0.4),
    GlyphVertex(18.5, 8.75),
  ], role: GlyphRole.line),
]);

const _g_chevronUp_ = Glyph([
  GlyphPolyline([
    GlyphVertex(5.5, 15.25),
    GlyphVertex(12, 8.75, 0.4),
    GlyphVertex(18.5, 15.25),
  ], role: GlyphRole.line),
]);

const _g_picker_ = Glyph([
  GlyphPolyline([
    GlyphVertex(7.5, 9.5),
    GlyphVertex(12, 5, 0.4),
    GlyphVertex(16.5, 9.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(7.5, 14.5),
    GlyphVertex(12, 19, 0.4),
    GlyphVertex(16.5, 14.5),
  ], role: GlyphRole.line),
]);

const _g_caretDown_ = Glyph([
  GlyphPolyline([
    GlyphVertex(5.2, 8, 1),
    GlyphVertex(18.8, 8, 1),
    GlyphVertex(12, 16, 1),
  ], closed: true),
]);

const _g_arrowUp_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 5),
    GlyphVertex(12, 19),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.5, 11.5),
    GlyphVertex(12, 5, 0.4),
    GlyphVertex(18.5, 11.5),
  ], role: GlyphRole.line),
]);

const _g_arrowDown_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 5),
    GlyphVertex(12, 19),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.5, 12.5),
    GlyphVertex(12, 19, 0.4),
    GlyphVertex(18.5, 12.5),
  ], role: GlyphRole.line),
]);

const _g_openExternal_ = Glyph([
  GlyphBox(3, 3, 21, 21, 3),
  GlyphPolyline([
    GlyphVertex(7.6, 16.4),
    GlyphVertex(16.4, 7.6),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(11, 7.6),
    GlyphVertex(16.4, 7.6, 0.4),
    GlyphVertex(16.4, 13),
  ], role: GlyphRole.detail),
]);

const _g_undo_ = Glyph([
  GlyphPolyline([
    GlyphVertex(5, 9),
    GlyphVertex(19, 9, 4.8),
    GlyphVertex(19, 18.6, 4.8),
    GlyphVertex(9, 18.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(8.8, 5.2),
    GlyphVertex(5, 9, 0.4),
    GlyphVertex(8.8, 12.8),
  ], role: GlyphRole.line),
], matchTextDirection: true);

const _g_redo_ = Glyph([
  GlyphPolyline([
    GlyphVertex(19, 9),
    GlyphVertex(5, 9, 4.8),
    GlyphVertex(5, 18.6, 4.8),
    GlyphVertex(15, 18.6),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(15.2, 5.2),
    GlyphVertex(19, 9, 0.4),
    GlyphVertex(15.2, 12.8),
  ], role: GlyphRole.line),
], matchTextDirection: true);

const _g_sync_ = Glyph([
  GlyphArc(
    12,
    12,
    7.78,
    math.pi * 1.144,
    math.pi * 0.889,
    role: GlyphRole.line,
  ),
  GlyphPolyline([
    GlyphVertex(5, 5),
    GlyphVertex(5, 8.6, 0.4),
    GlyphVertex(8.6, 8.6),
  ], role: GlyphRole.line),
  GlyphArc(
    12,
    12,
    7.78,
    math.pi * 0.144,
    math.pi * 0.889,
    role: GlyphRole.line,
  ),
  GlyphPolyline([
    GlyphVertex(19, 19),
    GlyphVertex(19, 15.4, 0.4),
    GlyphVertex(15.4, 15.4),
  ], role: GlyphRole.line),
]);

const _g_refresh_ = Glyph([
  GlyphArc(12, 12, 7.78, math.pi * 0.19, math.pi * 1.666, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(19, 5),
    GlyphVertex(19, 8.6, 0.4),
    GlyphVertex(15.4, 8.6),
  ], role: GlyphRole.line),
]);

const _g_reset_ = Glyph([
  GlyphArc(
    12,
    13.77,
    7.07,
    math.pi * 1.15,
    math.pi * -1.65,
    role: GlyphRole.line,
  ),
  GlyphPolyline([
    GlyphVertex(12, 6.7),
    GlyphVertex(9.9, 6.7),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(13.7, 10.5),
    GlyphVertex(9.9, 6.7, 0.4),
    GlyphVertex(13.7, 2.9),
  ], role: GlyphRole.line),
]);

const _g_export_ = Glyph([
  GlyphPolyline([
    GlyphVertex(8.4, 10.5),
    GlyphVertex(5, 10.5, 1.5),
    GlyphVertex(5, 21, 2.8),
    GlyphVertex(19, 21, 2.8),
    GlyphVertex(19, 10.5, 1.5),
    GlyphVertex(15.6, 10.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 15.6),
    GlyphVertex(12, 3),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(8.2, 6.8),
    GlyphVertex(12, 3, 0.4),
    GlyphVertex(15.8, 6.8),
  ], role: GlyphRole.line),
]);

const _g_upload_ = Glyph([
  GlyphPolyline([
    GlyphVertex(4.5, 16.4),
    GlyphVertex(4.5, 20, 2.2),
    GlyphVertex(19.5, 20, 2.2),
    GlyphVertex(19.5, 16.4),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 15.4),
    GlyphVertex(12, 3.5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(8.2, 7.3),
    GlyphVertex(12, 3.5, 0.4),
    GlyphVertex(15.8, 7.3),
  ], role: GlyphRole.line),
]);

const _g_add_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 5),
    GlyphVertex(12, 19),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5, 12),
    GlyphVertex(19, 12),
  ], role: GlyphRole.line),
]);

const _g_remove_ = Glyph([
  GlyphPolyline([
    GlyphVertex(5, 12),
    GlyphVertex(19, 12),
  ], role: GlyphRole.line),
]);

const _g_addCircle_ = Glyph([
  GlyphCircle(12, 12, 8.8, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(12, 7.8),
    GlyphVertex(12, 16.2),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(7.8, 12),
    GlyphVertex(16.2, 12),
  ], role: GlyphRole.line),
]);

const _g_removeCircle_ = Glyph([
  GlyphCircle(12, 12, 8.8, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(7.8, 12),
    GlyphVertex(16.2, 12),
  ], role: GlyphRole.line),
]);

const _g_close_ = Glyph([
  GlyphPolyline([GlyphVertex(6, 6), GlyphVertex(18, 18)], role: GlyphRole.line),
  GlyphPolyline([GlyphVertex(18, 6), GlyphVertex(6, 18)], role: GlyphRole.line),
]);

const _g_clearField_ = Glyph([
  GlyphCircle(12, 12, 8.8),
  GlyphPolyline([
    GlyphVertex(9.3, 9.3),
    GlyphVertex(14.7, 14.7),
  ], role: GlyphRole.detail),
  GlyphPolyline([
    GlyphVertex(14.7, 9.3),
    GlyphVertex(9.3, 14.7),
  ], role: GlyphRole.detail),
]);

const _g_check_ = Glyph([
  GlyphPolyline([
    GlyphVertex(4.8, 12.5),
    GlyphVertex(9.6, 17.3),
    GlyphVertex(19.4, 6.7),
  ], role: GlyphRole.line),
]);

const _g_checkDouble_ = Glyph([
  GlyphPolyline([
    GlyphVertex(2.9, 12.5),
    GlyphVertex(6.7, 16.3),
    GlyphVertex(14.45, 7.9),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(11.8, 16.3),
    GlyphVertex(13.2, 17.7),
    GlyphVertex(20.95, 9.3),
  ], role: GlyphRole.line),
]);

const _g_checkCircle_ = Glyph([
  GlyphCircle(12, 12, 8.8),
  GlyphPolyline([
    GlyphVertex(7.59, 12.3),
    GlyphVertex(10.49, 15.2),
    GlyphVertex(16.41, 8.79),
  ], role: GlyphRole.detail),
]);

const _g_block_ = Glyph([
  GlyphCircle(12, 12, 8.8, role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(5.78, 5.78),
    GlyphVertex(18.22, 18.22),
  ], role: GlyphRole.line),
]);

const _g_info_ = Glyph([
  GlyphCircle(12, 12, 8.8),
  GlyphCircle(12, 7.5, 1.4, role: GlyphRole.detail, solid: true),
  GlyphPolyline([
    GlyphVertex(12, 11.8),
    GlyphVertex(12, 16.7),
  ], role: GlyphRole.detail),
]);

const _g_warning_ = Glyph([
  GlyphPolyline([
    GlyphVertex(12, 1.6, 3),
    GlyphVertex(21.9, 20.3, 2.5),
    GlyphVertex(2.1, 20.3, 2.5),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(12, 9),
    GlyphVertex(12, 12.1),
  ], role: GlyphRole.detail),
  GlyphCircle(12, 16.2, 1.4, role: GlyphRole.detail, solid: true),
]);
