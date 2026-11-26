library;

import 'dart:math' as math;

import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

const rainbowAvatarPadding = 4.0;

const _ringWidth = 2.5;

const _ringGap = rainbowAvatarPadding - _ringWidth;

const _ringPeriod = Duration(seconds: 4);

class RainbowAvatarFrame extends StatefulWidget {
  const RainbowAvatarFrame({
    super.key,
    required this.size,
    required this.child,
  });

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

  final Animation<double> rotation;

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
    canvas.drawCircle(centre, radius, glow);
    canvas.drawCircle(centre, radius, ring);
  }

  @override
  bool shouldRepaint(_RainbowRingPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}
