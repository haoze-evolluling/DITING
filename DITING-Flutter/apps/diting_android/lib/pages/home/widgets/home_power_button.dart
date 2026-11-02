import 'dart:math' as math;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
// The shape names below come from material_new_shapes (which still owns `Morph` and
// `toPath`); hide material_ui's built-in copies so the import stays unambiguous.
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart'
    hide CornerRounding, MaterialShapes, RoundedPolygon;

/// Home power button: stopped, starting, running, stopping. Only the running state morphs:
/// knob and both halos grow into cookie9Sided together, so no layer keeps the old shape.
class HomePowerButton extends StatelessWidget {
  const HomePowerButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.runningLabel,
    this.stoppedLabel,
    this.busyLabel,
  });

  final PowerState state;
  final VoidCallback onPressed;
  final String? runningLabel;
  final String? stoppedLabel;
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final running = state.isRunning;
    final busy = state.isBusy;
    final l10n = context.l10n;
    final label = switch (state) {
      PowerState.starting ||
      PowerState.stopping => busyLabel ?? l10n.powerButtonStarting,
      PowerState.running => runningLabel ?? l10n.powerButtonStop,
      PowerState.stopped ||
      PowerState.error => stoppedLabel ?? l10n.powerButtonStart,
    };
    return Semantics(
      button: true,
      label: label,
      value: state.label(context.l10n),
      child: Center(
        // The knob only occupies the middle of the 240 box; dropping the caption below
        // lets the box shrink to the halo diameter instead of leaving dead space.
        child: SizedBox(
          width: 240,
          height: 176,
          child: _PowerVisual(
            running: running,
            busy: busy,
            foreground: running ? colorScheme.onPrimary : colorScheme.primary,
            onPressed: busy ? null : onPressed,
          ),
        ),
      ),
    );
  }
}

/// Three concentric shapes on one controller; size and color interpolate linearly, shape
/// uses easeOutBack of the same curve.
class _PowerVisual extends StatefulWidget {
  const _PowerVisual({
    required this.running,
    required this.busy,
    required this.foreground,
    required this.onPressed,
  });

  final bool running;
  final bool busy;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  State<_PowerVisual> createState() => _PowerVisualState();
}

class _PowerVisualState extends State<_PowerVisual>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 250);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: widget.running ? 1 : 0,
  );
  late final Animation<double> _morph = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(_PowerVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) {
      widget.running ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _lerp(double start, double end, double amount) =>
      start + (end - start) * amount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final primary = colorScheme.primary;
    final stoppedFill = colorScheme.surfaceContainerHigh;
    final runningShadow = BoxShadow(
      color: primary.withValues(alpha: 0.32),
      blurRadius: 28,
      offset: const Offset(0, 8),
    );
    final stoppedShadow = BoxShadow(
      color: Colors.black.withValues(alpha: 0.10),
      blurRadius: 12,
      offset: const Offset(0, 8),
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final amount = _controller.value;
        final shape = _MorphBorder(_morph.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            _Halo(
              shape: shape,
              size: _lerp(148, 172, amount),
              color: primary.withValues(alpha: _lerp(0, 0.10, amount)),
            ),
            _Halo(
              shape: shape,
              size: _lerp(124, 148, amount),
              color: primary.withValues(alpha: _lerp(0.06, 0.16, amount)),
            ),
            SizedBox.square(
              dimension: _lerp(92, 100, amount),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: shape,
                  color: Color.lerp(stoppedFill, primary, amount),
                  shadows: [
                    BoxShadow.lerp(stoppedShadow, runningShadow, amount)!,
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onPressed,
                    customBorder: shape,
                    child: Center(child: child),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.busy
          ? CommonCircleLoading(size: 42, color: widget.foreground)
          : GlyphIcon(
              widget.running ? AppGlyphs.bolt : AppGlyphs.playPause(0),
              size: 42,
              fill: 1,
              color: widget.foreground,
            ),
    );
  }
}

/// One halo layer: draws shape and color only, sized by the parent per frame.
class _Halo extends StatelessWidget {
  const _Halo({required this.shape, required this.size, required this.color});

  final ShapeBorder shape;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(shape: shape, color: color),
      ),
    );
  }
}

/// Interpolatable [ShapeBorder] between a circle and the nine-sided cookie.
class _MorphBorder extends ShapeBorder {
  const _MorphBorder(this.progress);

  final double progress;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) => _MorphBorder(progress);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final transform =
        Matrix4.translationValues(rect.center.dx, rect.center.dy, 0)
          ..rotateZ(progress * 2 * math.pi / 9)
          ..scaleByDouble(rect.width, rect.height, 1, 1)
          ..translateByDouble(-0.5, -0.5, 0, 1);
    return _morphPath(progress).transform(transform.storage);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  bool operator ==(Object other) =>
      other is _MorphBorder && other.progress == progress;

  @override
  int get hashCode => progress.hashCode;
}

/// Built once: Morph pairs its curves at construction, so keep it out of the per-frame paint path.
final _morph = Morph(MaterialShapes.circle, MaterialShapes.cookie9Sided);

Path _morphPath(double progress) =>
    _morph.toPath(progress: progress, rotationPivotX: 0.5, rotationPivotY: 0.5);
