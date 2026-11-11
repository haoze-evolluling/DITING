// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'liquid_glass.dart';

/// iOS 27's rim around a menu's or an alert's glass (.agents/architecture.md).
@immutable
class LiquidGlassRim {
  const LiquidGlassRim({
    required this.side,
    required this.corner,
    required this.flat,
    required this.shine,
  });

  factory LiquidGlassRim.alert(ColorScheme colorScheme) =>
      colorScheme.brightness == Brightness.dark
      ? const LiquidGlassRim(side: 0.75, corner: 0.1, flat: 0.03, shine: 0.22)
      : const LiquidGlassRim(side: 0.35, corner: 0.22, flat: 0.12, shine: 0.16);

  factory LiquidGlassRim.menu(ColorScheme colorScheme) =>
      colorScheme.brightness == Brightness.dark
      ? const LiquidGlassRim(side: 0.27, corner: 0.1, flat: 0.02, shine: 0.22)
      : const LiquidGlassRim(side: 0.25, corner: 0.15, flat: 0.09, shine: 0.16);

  final double side;
  final double corner;
  final double flat;

  /// Added light, not white laid over: iOS lifts dark and light panes alike.
  final double shine;

  LiquidGlassRim scale(double t) {
    final amount = t.clamp(0.0, 1.0);
    return LiquidGlassRim(
      side: side * amount,
      corner: corner * amount,
      flat: flat * amount,
      shine: shine * amount,
    );
  }

  /// The line, outside the pane; the pane given this rim draws the highlight.
  void paintLine(Canvas canvas, Rect rect, double radius) {
    if (rect.isEmpty) {
      return;
    }
    final round = _roundOf(rect.size, radius);
    final shape = AppRadius.all(round).toRSuperellipse(rect);
    final across = math.min(round / rect.width, 0.4);
    Color dark(double alpha) => Colors.black.withValues(alpha: alpha);
    canvas.drawRSuperellipse(
      shape.inflate(_hairlineWidth / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _hairlineWidth
        ..shader = LinearGradient(
          colors: [
            dark(side),
            dark(corner),
            dark(flat),
            dark(flat),
            dark(corner),
            dark(side),
          ],
          stops: [0, across / 4, across, 1 - across, 1 - across / 4, 1],
        ).createShader(rect),
    );
  }

  static double _roundOf(Size size, double radius) =>
      math.min(math.max(0.0, radius), size.shortestSide / 2);

  List<double> _uniforms(Size size, double radius) {
    final turns = _turns(size, _roundOf(size, radius));
    final ends = [for (final band in _shineBands) band.depth + band.width];
    return [
      for (final (turn, _) in turns) turn,
      for (final (_, lit) in turns) shine * lit,
      for (var index = 0; index < _shineSlots; index++)
        ends[math.min(index, ends.length - 1)],
      for (var index = 0; index < _shineSlots; index++)
        index < _shineBands.length ? _shineBands[index].lit : 0.0,
    ];
  }

  void _paintShine(Canvas canvas, Rect rect, double radius) {
    final round = _roundOf(rect.size, radius);
    final shape = AppRadius.all(round).toRSuperellipse(rect);
    final around = _sweepStops(rect.size, round);
    final stops = [for (final (stop, _) in around) stop];
    for (final band in _shineBands) {
      final alpha = shine * band.lit;
      // A ring, not a stroke: Impeller widens a stroke thinner than a pixel.
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRSuperellipse(shape.deflate(band.depth))
          ..addRSuperellipse(shape.deflate(band.depth + band.width)),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = SweepGradient(
            colors: [
              for (final (_, lit) in around)
                Colors.white.withValues(alpha: math.min(alpha * lit, 1)),
            ],
            stops: stops,
          ).createShader(rect),
      );
    }
  }

  static List<(double, double)> _turns(Size size, double round) {
    final halfWidth = size.width / 2;
    final halfHeight = size.height / 2;
    final turns = [(0.0, 1.0)];
    for (final (:along, :down, :lit) in _shineAround) {
      final turn = math.atan2(
        halfWidth - math.min(along * round, halfWidth),
        halfHeight - math.min(down * round, halfHeight),
      );
      turns.add((math.max(turns.last.$1, turn), lit));
    }
    turns.add((math.pi / 2, 0));
    return turns;
  }

  static List<(double, double)> _sweepStops(Size size, double round) {
    final turns = _turns(size, round);
    const full = 2 * math.pi;
    return [
      for (final (turn, lit) in turns.reversed)
        ((math.pi / 2 - turn) / full, lit),
      for (final (turn, lit) in turns.skip(1))
        ((math.pi / 2 + turn) / full, lit),
      for (final (turn, lit) in turns.reversed.skip(1))
        ((math.pi * 1.5 - turn) / full, lit),
      for (final (turn, lit) in turns.skip(1))
        ((math.pi * 1.5 + turn) / full, lit),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassRim &&
      other.side == side &&
      other.corner == corner &&
      other.flat == flat &&
      other.shine == shine;

  @override
  int get hashCode => Object.hash(side, corner, flat, shine);
}

/// Light a press casts on a pane: [strength] at [center], falling off to [wash] over [reach].
@immutable
class LiquidGlassGlow {
  const LiquidGlassGlow({
    required this.center,
    required this.reach,
    required this.strength,
    this.wash = 0,
  });

  static const none = LiquidGlassGlow(
    center: Offset.zero,
    reach: 1,
    strength: 0,
  );

  final Offset center;
  final double reach;
  final double strength;
  final double wash;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassGlow &&
      other.center == center &&
      other.reach == reach &&
      other.strength == strength &&
      other.wash == wash;

  @override
  int get hashCode => Object.hash(center, reach, strength, wash);
}
