// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'popup.dart';

/// The parts of the morph that draw the droplet, its shadows and its content.
extension on _RenderPopupMorph {
  _Opening _openingOf(double time, Rect card) {
    final anchor = _localAnchor;
    final progress = _open.x(time);
    final scale = lerpDouble(
      _platterInControl * anchor.shortestSide / card.width,
      1,
      progress,
    )!;
    final height = lerpDouble(card.width, card.height, progress)!;
    final toCard = card.center.dy - anchor.center.dy;
    final distance = toCard.abs();
    final dip = _sourceImage == null
        ? 0.0
        : toCard.sign *
              (math.min(1.0, distance / 30) * 23 + 0.124 * distance) *
              riseAndFall(time, 0.098, 3.3);
    final platter = Rect.fromCenter(
      center:
          Offset.lerp(anchor.center, card.center, progress)! + Offset(0, dip),
      width: math.max(0.0, card.width * scale),
      height: math.max(0.0, height * scale),
    );
    final corners =
        _cardRadius +
        card.width *
            _cornersReachPerWidth *
            _corners.x(math.max(0.0, time - _cornersDelay));
    Rect? droplet;
    if (_sourceImage != null) {
      final extent = anchor.size * lerpDouble(1, _dropletShare, progress)!;
      final inner = card.deflate(
        anchor.longestSide * _dropletShare / 2 + _dropletBlend + _rimDepth,
      );
      final sunk = Offset.lerp(anchor.center, card.center, _dropletShare)!;
      final target = inner.isEmpty
          ? card.center
          : Offset(
              sunk.dx.clamp(inner.left, inner.right),
              sunk.dy.clamp(inner.top, inner.bottom),
            );
      droplet = Rect.fromCenter(
        center: Offset.lerp(anchor.center, target, progress)!,
        width: extent.width,
        height: extent.height,
      );
    }
    return (
      platter: platter,
      radius: math.max(0.0, math.min(height / 2, corners) * scale),
      droplet: droplet,
      progress: progress,
    );
  }

  /// The return into the control [time] seconds on, from [start] or the card.
  void _paintReturn(
    PaintingContext context,
    Offset offset,
    _MorphFrame? start,
    double time,
  ) {
    final image = _sourceImage!.value;
    if (image == null) {
      return;
    }
    final anchor = _localAnchor;
    final bounds = Offset.zero & size;
    final card = _closingSurface ?? bounds;
    if (card.isEmpty) {
      _pane.clear();
      return;
    }
    final opening = start == null ? null : _openingOf(start.time, card);
    final from = opening?.platter ?? card;
    final fromRadius = opening?.radius ?? _cardRadius;
    final fromDroplet =
        opening?.droplet ??
        Rect.fromCenter(
          center: Offset.lerp(anchor.center, from.center, _dropletShare)!,
          width: anchor.width * _dropletShare,
          height: anchor.height * _dropletShare,
        );
    // The springs still ring a little when the route ends; ease that out so
    // the control takes over exactly where the droplet lands.
    final ringing =
        1 - Curves.easeIn.transform(((time - 0.4) / 0.1).clamp(0.0, 1.0));
    final progress = 1 + (_droplet.x(time) - 1) * ringing;
    final toCard = from.center.dy - anchor.center.dy;
    final away = toCard.sign;
    final dip =
        math.min(0.21 * toCard.abs(), 22.0) * riseAndFall(time, 0.072, 2.4);
    final lift =
        math.min(0.25 * toCard.abs(), 19.0) * riseAndFall(time, 0.176, 4.9);
    final scale = lerpDouble(
      1,
      _platterInControl *
          anchor.shortestSide /
          math.max(from.width, from.height),
      progress,
    )!;
    final platter = Rect.fromCenter(
      center:
          Offset.lerp(from.center, anchor.center, progress)! +
          Offset(0, away * dip * ringing),
      width: math.max(0.0, from.width * scale),
      height: math.max(
        0.0,
        lerpDouble(from.height, from.width, progress)! * scale,
      ),
    );
    final platterRadius = math.max(
      0.0,
      lerpDouble(fromRadius, from.width / 2, progress)! * scale,
    );
    final droplet = Rect.fromCenter(
      center:
          Offset.lerp(fromDroplet.center, anchor.center, progress)! -
          Offset(0, away * lift * ringing),
      width: lerpDouble(fromDroplet.width, anchor.width, progress)!,
      height: lerpDouble(fromDroplet.height, anchor.height, progress)!,
    );
    final absorbed = _dropletAbsorbed.transform(
      (time / _dismissSeconds).clamp(0.0, 1.0),
    );
    final blend = _dropletBlend * math.min(1.0, time / 0.05) * (1 - absorbed);
    final glass = _glass;
    final outline = gooPairOutline(
      platter,
      platterRadius,
      droplet,
      blend,
      coarse: glass?.coarse ?? false,
    );
    final shape = outline.getBounds();
    final reveal =
        (opening?.progress.clamp(0.0, 1.0) ?? 1) *
        (1 -
            Curves.easeOut.transform(
              (time / _dropletContentOut).clamp(0.0, 1.0),
            ));
    final remaining = (1 - progress).clamp(0.0, 1.0);
    final path = outline.shift(offset);
    if (glass != null) {
      _pane.paint(
        context,
        shape.shift(offset),
        shape: LiquidGlassGoo(
          outline.shift(-shape.topLeft),
          [platter.shift(-shape.topLeft), droplet.shift(-shape.topLeft)],
          [blend],
          firstRadius: math.max(platterRadius, 1e-3),
        ),
        style: LiquidGlassStyle.lerp(
          glass.from,
          glass.to,
          remaining,
        ).copyWith(blur: lerpDouble(glass.to.blur, glass.from.blur, absorbed)),
        hold: bounds
            .expandToInclude(from)
            .expandToInclude(anchor.inflate(anchor.longestSide))
            .inflate(size.longestSide * _overshootPerLongestSide)
            .shift(offset),
        holdFrost: absorbed > 0 ? glass.from.blur : null,
      );
    }
    // Returning cards keep their own shadow as they fade into the platter's,
    // which fills under them from the start so the page does not show
    // through; on glass they stand bare and the platter holds throughout.
    _paintShadows(
      context.canvas,
      path,
      platter.shift(offset),
      platterRadius,
      remaining * (glass == null ? 1 - reveal : 1.0),
    );
    final Color fill;
    if (glass == null) {
      fill = Color.lerp(_surfaceColor, _sourceColor, progress)!;
    } else {
      fill = _sourceColor.withValues(alpha: _sourceColor.a * (1 - remaining));
    }
    context.canvas.drawPath(path, Paint()..color = fill);
    _paintSource(
      context.canvas,
      image,
      droplet.shift(offset),
      lerpDouble(
        0.2,
        1,
        _dropletGlyphCurve.transform((time / _dropletGlyphIn).clamp(0.0, 1.0)),
      )!,
    );
    if (reveal > 0 && !size.isEmpty) {
      _paintContent(
        context,
        offset,
        reveal,
        _maxContentBlur * (1 - reveal),
        _contentTransform(
          platter,
          math.min(platter.width / card.width, platter.height / card.height),
          content: card,
        ),
      );
    }
  }

  void _paintShadows(
    Canvas canvas,
    Path path,
    Rect rect,
    double radius,
    double strength,
  ) {
    final reach = _shadows.fold(
      0.0,
      (reach, shadow) =>
          math.max(reach, shadow.blurSigma * 3 + shadow.offset.distance),
    );
    // The blur shades under the platter too; keep that out of fading content.
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(path.getBounds().inflate(reach))
          ..addPath(path, Offset.zero),
      );
    final corners = AppRadius.all(radius);
    for (final shadow in _shadows) {
      canvas.drawRSuperellipse(
        corners.toRSuperellipse(rect.shift(shadow.offset)),
        shadow.toPaint()
          ..color = shadow.color.withValues(alpha: shadow.color.a * strength),
      );
    }
    canvas.restore();
  }

  void _paintSource(
    Canvas canvas,
    ui.Image image,
    Rect rect,
    double opacity, {
    double blur = 0,
  }) {
    if (Color.getAlphaFromOpacity(opacity) == 0) {
      return;
    }
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..filterQuality = FilterQuality.medium
        ..imageFilter = blur > 0
            ? ImageFilter.blur(sigmaX: blur, sigmaY: blur)
            : null,
    );
  }

  void _paintContent(
    PaintingContext context,
    Offset offset,
    double reveal,
    double blur,
    Matrix4 transform,
  ) {
    void paintChild(PaintingContext context, Offset offset) =>
        context.pushTransform(
          needsCompositing,
          offset,
          transform,
          (context, offset) => context.paintChild(child!, offset),
        );
    void paintBlurred(PaintingContext context, Offset offset) {
      if (blur < _unseenBlur) {
        paintChild(context, offset);
        return;
      }
      context.pushLayer(
        ImageFilterLayer(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        ),
        paintChild,
        offset,
      );
    }

    final alpha = Color.getAlphaFromOpacity(reveal);
    if (alpha == 255) {
      paintBlurred(context, offset);
      return;
    }
    context.pushOpacity(offset, alpha, paintBlurred);
  }

  Matrix4 _contentTransform(Rect rect, double scale, {Rect? content}) {
    final source = content ?? Offset.zero & size;
    return Matrix4.translationValues(rect.center.dx, rect.center.dy, 0)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-source.center.dx, -source.center.dy, 0, 1);
  }
}
