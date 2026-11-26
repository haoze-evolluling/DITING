// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:math' as math;

import 'package:diting_android/ui/context.dart';
import 'package:diting_android/ui/inherited.dart';
import 'package:diting_android/ui/shape.dart';
import 'package:diting_android/ui/surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import 'goo.dart';
import 'liquid_glass.dart';
import 'navigation_dock.dart';

part 'button_hover_mark.dart';


enum TonalButtonSize {
  bar(button: 44, icon: 24),
  docked(button: BottomInsetScope.dockedSearchHeight, icon: 24),
  section(button: 36, icon: 20),
  compact(button: 32, icon: 20);

  const TonalButtonSize({required this.button, required this.icon});

  final double button;
  final double icon;
}

class TonalButtonGroup extends StatefulWidget {
  const TonalButtonGroup({
    super.key,
    this.size = TonalButtonSize.bar,
    required this.children,
  });

  final TonalButtonSize size;
  final List<Widget> children;

  @override
  State<TonalButtonGroup> createState() => _TonalButtonGroupState();
}

class _TonalButtonGroupState extends State<TonalButtonGroup>
    with TickerProviderStateMixin {
  final _pointer = ValueNotifier<int?>(null);
  _HoverMark? _mark;

  @override
  void dispose() {
    _pointer.dispose();
    _mark?.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer.value == null && event.buttons & kPrimaryButton != 0) {
      _pointer.value = event.pointer;
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (event.pointer == _pointer.value) {
      _pointer.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final row = Row(mainAxisSize: MainAxisSize.min, children: widget.children);
    final mark = widget.children.length > 1 ? _mark ??= _HoverMark(this) : null;
    final buttons = TonalButtonTheme(
      grouped: true,
      size: widget.size,
      child: mark == null
          ? row
          : _HoverMarkScope(mark: mark, child: mark.build(context, row)),
    );
    if (GooSurface.of(context)) {
      return ElasticPress(child: GooPane(child: buttons));
    }
    return ElasticPress(
      child: TonalButtonTheme.glassOf(context)
          ? Listener(
              onPointerDown: _handlePointerDown,
              onPointerUp: _handlePointerEnd,
              onPointerCancel: _handlePointerEnd,
              child: ValueListenableBuilder(
                valueListenable: _pointer,
                builder: (_, pointer, child) => LiquidGlass(
                  style: LiquidGlassStyle.regular(colorScheme),
                  pressed: pointer != null,
                  child: child,
                ),
                child: buttons,
              ),
            )
          : DecoratedBox(
              decoration: ShapeDecoration(
                color: context.raisedSurfaceLevel.colorOf(colorScheme),
                shape: AppShape.standard,
              ),
              child: buttons,
            ),
    );
  }
}

class TonalButton extends StatelessWidget {
  const TonalButton({
    super.key,
    this.size = TonalButtonSize.section,
    this.glyph,
    required this.label,
    required this.onPressed,
  });

  final TonalButtonSize size;
  final IconData? glyph;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final glyph = this.glyph;
    final label = Text(this.label);
    return ElasticPress(
      enabled: onPressed != null,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
          shape: AppShape.standard,
        ),
        child: TonalButtonTheme(
          grouped: true,
          size: size,
          child: glyph == null
              ? FilledButton(onPressed: onPressed, child: label)
              : FilledButton.icon(
                  onPressed: onPressed,
                  icon: Icon(glyph),
                  label: label,
                ),
        ),
      ),
    );
  }
}

class TonalButtonTheme extends StatelessWidget {
  const TonalButtonTheme({
    super.key,
    this.grouped = false,
    this.glass = false,
    this.size = TonalButtonSize.bar,
    required this.child,
  });

  final bool grouped;
  final bool glass;
  final TonalButtonSize size;
  final Widget child;

  static bool glassOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassButtons>()?.glass ??
      false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final goo = !grouped && GooSurface.of(context);
    final paned = glass && !grouped && !goo;
    final fill = grouped || paned || goo
        ? Colors.transparent
        : context.raisedSurfaceLevel.colorOf(colorScheme);
    final foreground = colorScheme.onSurface;
    final disabledForeground = foreground.withValues(alpha: 0.38);
    ButtonStyle? paneOf(bool Function(Set<WidgetState> states) tinted) {
      if (!paned) {
        return null;
      }
      final regularGlass = LiquidGlassStyle.regular(colorScheme);
      final tintedGlass = LiquidGlassStyle.tinted(
        colorScheme,
        colorScheme.primary,
      );
      return LiquidGlass.buttonStyle(
        (states) => tinted(states) ? tintedGlass : regularGlass,
      );
    }

    ButtonStyle feedback(ButtonStyle? pane, {required bool standsOff}) {
      final behind = pane?.backgroundBuilder;
      return ButtonStyle(
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: pane?.backgroundColor,
        backgroundBuilder: (context, states, child) {
          final content = behind == null
              ? child!
              : behind(context, states, child);
          final mark = _HoverMarkScope.maybeOf(context);
          return mark == null
              ? ElasticHover(child: content)
              : _HoverSlot(
                  mark: mark,
                  enabled: !states.contains(WidgetState.disabled),
                  child: content,
                );
        },
      ).merge(focusRingStyle(colorScheme, standsOff: standsOff));
    }

    final iconPane = goo
        ? GooSurface.buttonStyle
        : paneOf((states) => states.contains(WidgetState.selected));
    final filledPane = paneOf(
      (states) => !states.contains(WidgetState.disabled),
    );
    final filledFeedback = feedback(filledPane, standsOff: !grouped);
    final themed = IconButtonTheme(
      data: IconButtonThemeData(
        style: feedback(iconPane, standsOff: paned).merge(
          IconButton.styleFrom(
            backgroundColor: fill,
            foregroundColor: foreground,
            disabledBackgroundColor: fill,
            disabledForegroundColor: disabledForeground,
            fixedSize: Size.square(size.button),
            minimumSize: Size.square(size.button),
            padding: EdgeInsets.zero,
            iconSize: size.icon,
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
      child: FilledButtonTheme(
        data: FilledButtonThemeData(
          style: filledFeedback.merge(
            FilledButton.styleFrom(
              backgroundColor: grouped ? fill : null,
              foregroundColor: grouped
                  ? foreground
                  : paned
                  ? colorScheme.onPrimary
                  : null,
              disabledBackgroundColor: grouped ? fill : null,
              disabledForegroundColor: grouped ? disabledForeground : null,
              minimumSize: Size.square(size.button),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: AppShape.standard,
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        child: child,
      ),
    );
    return _GlassButtons(glass: paned, child: themed);
  }
}

class _GlassButtons extends InheritedWidget {
  const _GlassButtons({required this.glass, required super.child});

  final bool glass;

  @override
  bool updateShouldNotify(_GlassButtons oldWidget) => glass != oldWidget.glass;
}
