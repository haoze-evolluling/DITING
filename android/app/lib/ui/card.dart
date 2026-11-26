// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

import 'package:diting_android/ui/context.dart';
import 'package:diting_android/ui/focus.dart';
import 'package:diting_android/ui/shape.dart';
import 'package:diting_android/ui/surface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'fade_box.dart';

class Info {
  final String label;
  final IconData? glyph;

  const Info({required this.label, this.glyph});
}


const commonCardIconSize = 20.0;

class CommonCard extends StatelessWidget {
  const CommonCard({
    super.key,
    bool? isSelected,
    this.onPressed,
    this.radius,
    this.padding,
    this.enterAnimated = false,
    this.shape,
    this.isError = false,
    this.enterActionsOnRight = false,
    this.statesController,
    this.inert = false,
    this.fillsSelection = false,
    required this.child,
  }) : isSelected = isSelected ?? false;

  final bool inert;
  final bool enterAnimated;
  final bool enterActionsOnRight;

  final bool isSelected;
  final bool fillsSelection;
  final bool isError;
  final void Function()? onPressed;
  final Widget child;

  final EdgeInsets? padding;
  final double? radius;
  final OutlinedBorder? shape;
  final WidgetStatesController? statesController;

  BorderSide _buildBorderSide(
    BuildContext context,
    Set<WidgetState> states, {
    required bool ringed,
  }) {
    if (!ringed || !states.contains(WidgetState.focused)) {
      return shape?.side ?? BorderSide.none;
    }
    final colorScheme = context.colorScheme;
    final side = focusRingSide(colorScheme);
    return isError ? side.copyWith(color: colorScheme.error) : side;
  }

  bool get _filled => isSelected && fillsSelection;

  Color _buildBackgroundColor(BuildContext context, SurfaceLevel level) {
    final colorScheme = context.colorScheme;
    if (isError) {
      return colorScheme.errorContainer;
    }
    if (_filled) {
      return colorScheme.primary;
    }
    return level.colorOf(colorScheme);
  }

  Color _buildForegroundColor(BuildContext context) {
    final colorScheme = context.colorScheme;
    if (isError) {
      return colorScheme.onErrorContainer;
    }
    if (_filled) {
      return colorScheme.onPrimary;
    }
    return colorScheme.onSurfaceVariant;
  }

  Color _buildIconColor(BuildContext context) {
    final colorScheme = context.colorScheme;
    if (isError) {
      return colorScheme.onErrorContainer;
    }
    if (_filled) {
      return colorScheme.onPrimary;
    }
    return colorScheme.primary;
  }

  Widget _buildButton(BuildContext context, SurfaceLevel level) {
    final iconColor = _buildIconColor(context);
    final foregroundColor = _buildForegroundColor(context);
    final remote = RemoteFocusAdapter.isEnabledOf(context);
    return ValueListenableBuilder(
      valueListenable: FocusMovedByKey.instance,
      builder: (context, movedByKey, content) => FilledButton(
        statesController: statesController,
        clipBehavior: Clip.antiAlias,
        style:
            FilledButton.styleFrom(
              padding: padding ?? EdgeInsets.zero,
              shape: shape ?? AppShape.all(radius ?? AppCorner.standard),
              iconSize: commonCardIconSize,
              iconColor: iconColor,
              foregroundColor: foregroundColor,
              disabledIconColor: inert ? iconColor : null,
              disabledForegroundColor: inert ? foregroundColor : null,
              elevation: 0,
            ).copyWith(
              backgroundColor: WidgetStatePropertyAll(
                _buildBackgroundColor(context, level),
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => _buildBorderSide(
                  context,
                  states,
                  ringed: remote || movedByKey,
                ),
              ),
            ),
        onPressed: inert ? null : onPressed,
        child: content,
      ),
      child: Semantics(
        selected: isSelected ? true : null,
        child: SurfaceScope(level: level, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = _buildButton(context, context.raisedSurfaceLevel);
    final card = !enterActionsOnRight
        ? button
        : Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent ||
                  event.logicalKey != LogicalKeyboardKey.arrowRight) {
                return KeyEventResult.ignored;
              }
              final focusNode = FocusManager.instance.primaryFocus;
              final context = focusNode?.context;
              if (focusNode == null || context == null) {
                return KeyEventResult.ignored;
              }
              final action = focusNode.descendants
                  .where((node) => node.skipTraversal && node.canRequestFocus)
                  .firstOrNull;
              if (action != null) {
                action.requestFocus();
                return KeyEventResult.handled;
              }
              if (focusNode.skipTraversal ||
                  context.findAncestorWidgetOfExactType<IconButton>() != null) {
                return KeyEventResult.ignored;
              }
              return focusNode.nextFocus()
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored;
            },
            child: button,
          );

    return switch (enterAnimated) {
      true => FadeScaleEnterBox(child: card),
      false => card,
    };
  }
}
