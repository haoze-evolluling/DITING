// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'app_glyphs.dart';

const _g_wifi_ = Glyph([
  GlyphPath('M3.32 9.56 A13.5 13.5 0 0 1 20.68 9.56', role: GlyphRole.line),
  GlyphPath('M6.54 13.39 A8.5 8.5 0 0 1 17.46 13.39', role: GlyphRole.line),
  GlyphCircle(12, 18.6, 1.7, role: GlyphRole.line, solid: true),
]);

const _g_wifiOff_ = Glyph([
  GlyphPath('M3.32 9.56 A13.5 13.5 0 0 1 6.15 7.73', role: GlyphRole.line),
  GlyphPath('M10.75 6.46 A13.5 13.5 0 0 1 20.68 9.56', role: GlyphRole.line),
  GlyphPath('M6.54 13.39 A8.5 8.5 0 0 1 10.56 11.52', role: GlyphRole.line),
  GlyphPath('M15.27 12.05 A8.5 8.5 0 0 1 17.46 13.39', role: GlyphRole.line),
  GlyphCircle(12, 18.6, 1.7, role: GlyphRole.line, solid: true),
  GlyphPolyline([
    GlyphVertex(4.5, 3),
    GlyphVertex(20.5, 19),
  ], role: GlyphRole.line),
]);

const _g_gavel_ = Glyph([
  GlyphPolyline([
    GlyphVertex(14.93, 7.15, 1.5),
    GlyphVertex(11.25, 3.47, 1.5),
    GlyphVertex(3.47, 11.25, 1.5),
    GlyphVertex(7.15, 14.93, 1.5),
  ], closed: true),
  GlyphPolyline([
    GlyphVertex(11.04, 11.04),
    GlyphVertex(19.8, 19.8),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(3.2, 20.5),
    GlyphVertex(11.5, 20.5),
  ], role: GlyphRole.line),
]);

const _g_appsList_ = Glyph([
  GlyphBox(3.5, 3.3, 6.9, 6.7, 1),
  GlyphBox(3.5, 10.3, 6.9, 13.7, 1),
  GlyphBox(3.5, 17.3, 6.9, 20.7, 1),
  GlyphPolyline([
    GlyphVertex(10.5, 5),
    GlyphVertex(20.5, 5),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(10.5, 12),
    GlyphVertex(20.5, 12),
  ], role: GlyphRole.line),
  GlyphPolyline([
    GlyphVertex(10.5, 19),
    GlyphVertex(20.5, 19),
  ], role: GlyphRole.line),
]);

const _g_iconTile_ = Glyph([
  GlyphBox(3, 3, 21, 21, 5),
  GlyphPolyline([
    GlyphVertex(5.6, 16.8),
    GlyphVertex(9.6, 12.8, 0.8),
    GlyphVertex(12.8, 16, 0.8),
    GlyphVertex(14.6, 14.2, 0.8),
    GlyphVertex(18.4, 18),
  ], role: GlyphRole.detail),
  GlyphCircle(15.2, 8.8, 1.5, role: GlyphRole.detail, solid: true),
]);

Glyph _g_sidebar_(double progress) {
  final divider = lerpDouble(8.5, 11.5, progress)!;
  return Glyph([
    const GlyphBox(3, 4.5, 21, 19.5, 3.5),
    GlyphPolyline([
      GlyphVertex(divider, 4.5),
      GlyphVertex(divider, 19.5),
    ], role: GlyphRole.detail),
    for (final y in const [8.5, 11.0, 13.5])
      GlyphPolyline([
        GlyphVertex(5.5, y),
        GlyphVertex(divider - 2.5, y),
      ], role: GlyphRole.detail),
  ], matchTextDirection: true);
}

/// Play at 0, pause at 1; past either end it keeps turning, so it bounces.
Glyph _g_playPause_(double progress) {
  final fold = progress.clamp(0.0, 1.0);
  final turn = math.pi / 2 * progress;
  if (fold == 0) {
    return Glyph([
      GlyphPolyline([
        for (final corner in _g__playCorners_) _g__turnedVertex_(corner, turn),
      ], closed: true),
    ]);
  }
  return Glyph([
    for (final (half, bar) in _g__playHalves_)
      GlyphPolyline([
        for (var i = 0; i < bar.length; i++)
          _g__turnedVertex_(Offset.lerp(half[i], bar[i], fold)!, turn),
      ], closed: true),
  ]);
}

const _g__playCorners_ = [
  Offset(8.3, 5.6),
  Offset(18.8, 12),
  Offset(8.3, 18.4),
];

const _g__playHalves_ = [
  (
    [Offset(8.3, 5.6), Offset(18.8, 12), Offset(18.8, 12), Offset(8.3, 12)],
    [Offset(5.9, 6.9), Offset(18.1, 6.9), Offset(18.1, 9.1), Offset(5.9, 9.1)],
  ),
  (
    [Offset(8.3, 12), Offset(18.8, 12), Offset(18.8, 12), Offset(8.3, 18.4)],
    [
      Offset(5.9, 14.9),
      Offset(18.1, 14.9),
      Offset(18.1, 17.1),
      Offset(5.9, 17.1),
    ],
  ),
];

GlyphVertex _g__turnedVertex_(Offset corner, double angle) {
  final offset = corner - const Offset(12, 12);
  return GlyphVertex(
    12 + offset.dx * math.cos(angle) - offset.dy * math.sin(angle),
    12 + offset.dx * math.sin(angle) + offset.dy * math.cos(angle),
    1.2,
  );
}

Glyph _g_backFor_(TargetPlatform platform) {
  if (kIsWeb) {
    return _g_arrowBack_;
  }
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => _g_chevronBack_,
    _ => _g_arrowBack_,
  };
}
