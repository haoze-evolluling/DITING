/// Flowing rainbow halo around an avatar, used by the recognition lists for a member the cloud
/// document marks with `"frame": "rainbow"`.
///
/// The avatar keeps its tile size: the ring is drawn *inside* [RainbowAvatarFrame]'s square, so a
/// decorated row stays exactly as tall as every other row. The painter ignores the box bounds for
/// the outer glow, which is what makes the halo bleed into the list padding instead of clipping.
library;

import 'dart:math' as math;

import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Space the ring and its gap take on each side of the avatar.
const rainbowAvatarPadding = 4.0;

/// Thickness of the coloured ring itself.
const _ringWidth = 2.5;

/// Air between the photo's edge and the ring.
const _ringGap = rainbowAvatarPadding - _ringWidth;

/// One full turn; slow enough to read as a flow rather than a spinner.
const _ringPeriod = Duration(seconds: 4);

/// A circular avatar of `size` with a rotating rainbow ring just inside its edge.
class RainbowAvatarFrame extends StatefulWidget {
  const RainbowAvatarFrame({
    super.key,
    required this.size,
    required this.child,
  });

  /// Outer diameter; the avatar inside is [rainbowAvatarPadding] smaller on each side.
  final double size;

  final Widget child;

  @override
  State<RainbowAvatarFrame> createState() => _RainbowAvatarFrameState();
}

class _RainbowAvatarFrameState extends State<RainbowAvatarFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: _ringPeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A device that asked for no animation still gets the halo, just holding one angle.
    if (context.disableAnimations) {
      _rotation.stop();
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        // The glow is painted past the square on purpose; clipping would cut it off.
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RainbowRingPainter(rotation: _rotation),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _RainbowRingPainter extends CustomPainter {
  _RainbowRingPainter({required this.rotation}) : super(repaint: rotation);

  /// 0→1 per turn, driving the gradient's angle.
  final Animation<double> rotation;

  /// A closed hue wheel in the app's saturated accent range; the last colour repeats the first so
  /// the sweep gradient has no seam.
  static const _colours = [
    Color(0xFFFF4D6D),
    Color(0xFFFF8A3D),
    Color(0xFFFFD23F),
    Color(0xFF5BD98A),
    Color(0xFF3EC7F0),
    Color(0xFF6C7BFF),
    Color(0xFFDA5BE8),
    Color(0xFFFF4D6D),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    // Sits in the gap the frame reserved, so the ring never covers the photo.
    final radius =
        size.shortestSide / 2 -
        rainbowAvatarPadding +
        _ringGap +
        _ringWidth / 2;
    final circle = Rect.fromCircle(center: centre, radius: radius);
    final shader = SweepGradient(
      colors: _colours,
      transform: GradientRotation(rotation.value * 2 * math.pi),
    ).createShader(circle);
    final glow = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringWidth
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final ring = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringWidth;
    // The soft pass first, then the crisp ring on top.
    canvas.drawCircle(centre, radius, glow);
    canvas.drawCircle(centre, radius, ring);
  }

  @override
  bool shouldRepaint(_RainbowRingPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}
