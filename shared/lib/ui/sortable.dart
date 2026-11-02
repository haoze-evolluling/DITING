// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:diting_shared/ui/l10n.dart';
import 'package:diting_shared/ui/models.dart';
import 'package:diting_shared/ui/motion.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'focus.dart';
part 'sortable_a.dart';

/// The sort mode a [CommonScaffold] keeps for its body, or a section for its own rows.
class SortModeScope extends InheritedWidget {
  const SortModeScope({super.key, required this.sorting, required super.child});

  final bool sorting;

  static SortModeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SortModeScope>();

  @override
  bool updateShouldNotify(SortModeScope oldWidget) =>
      sorting != oldWidget.sorting;
}

typedef SortableItemData = ({int index, bool sorting});

/// While a scope above sorts, rows below give up taps and menus for a [SortHandle].
class SortableItem extends StatelessWidget {
  const SortableItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static SortableItemData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SortableItemScope>()?.data;

  static bool isSorting(BuildContext context) =>
      maybeOf(context)?.sorting ?? false;

  @override
  Widget build(BuildContext context) {
    final sorting = SortModeScope.maybeOf(context)?.sorting ?? false;
    return _SortableItemScope(
      data: (index: index, sorting: sorting),
      // Long-pressing a row anywhere lifts it, as an iOS list does.
      child: ReorderableDelayedDragStartListener(
        index: index,
        enabled: sorting,
        child: child,
      ),
    );
  }
}

class _SortableItemScope extends InheritedWidget {
  const _SortableItemScope({required this.data, required super.child});

  final SortableItemData data;

  @override
  bool updateShouldNotify(_SortableItemScope oldWidget) =>
      data != oldWidget.data;
}

class DisclosureIndicator extends StatelessWidget {
  const DisclosureIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: kMinInteractiveDimension,
      child: Center(child: GlyphIcon(AppGlyphs.chevronForward)),
    );
  }
}

/// A row's trailing button doing something else, held to the [DisclosureIndicator]'s box.
class DetailButton extends StatelessWidget {
  const DetailButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
  });

  final Glyph glyph;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: kMinInteractiveDimension,
      child: Center(
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: GlyphIcon(glyph),
        ),
      ),
    );
  }
}

/// Its row drags; with focus, a select key lifts the row and the up and down
/// keys move it, so a remote or a keyboard can sort without a pointer.
class SortHandle extends StatefulWidget {
  const SortHandle({super.key, required this.index});

  final int index;

  @override
  State<SortHandle> createState() => _SortHandleState();
}

class _SortHandleState extends State<SortHandle> {
  var _focused = false;
  var _lifted = false;

  @override
  void didUpdateWidget(SortHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index || !_focused) {
      return;
    }
    final policy = widget.index > oldWidget.index
        ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
        : ScrollPositionAlignmentPolicy.keepVisibleAtStart;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: policy,
          duration: context.motionDuration(kThemeAnimationDuration),
        );
      }
    });
  }

  void _handleFocusChange(bool focused) {
    setState(() {
      _focused = focused;
      _lifted = _lifted && focused;
    });
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    if (remoteSelectKeys.contains(key) || key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        setState(() {
          _lifted = !_lifted;
        });
      }
      return KeyEventResult.handled;
    }
    if (!_lifted || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _lifted = false;
      });
      return KeyEventResult.handled;
    }
    final offset = switch (key) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowRight => 0,
      _ => null,
    };
    if (offset == null) {
      return KeyEventResult.ignored;
    }
    final list = SliverReorderableList.maybeOf(context)?.widget;
    final target = widget.index + offset;
    if (offset != 0 && list != null && target >= 0 && target < list.itemCount) {
      list.onReorderItem?.call(widget.index, target);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    const dimension = kMinInteractiveDimension;
    return Semantics(
      button: true,
      label: UiLocalizations.of(context).sort,
      child: Focus(
        onFocusChange: _handleFocusChange,
        onKeyEvent: _handleKey,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: ColoredBox(
            color: Colors.transparent,
            child: SizedBox.square(
              dimension: dimension,
              child: Center(
                child: AnimatedContainer(
                  duration: context.motionDuration(kThemeAnimationDuration),
                  width: dimension - 8,
                  height: dimension - 8,
                  decoration: ShapeDecoration(
                    shape: AppShape.circle,
                    color: colorScheme.onSurface.withValues(
                      alpha: _lifted
                          ? 0.16
                          : _focused
                          ? 0.12
                          : 0,
                    ),
                  ),
                  child: Center(
                    child: GlyphIcon(
                      AppGlyphs.dragHandle,
                      color: _lifted ? colorScheme.primary : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _enterDuration = Duration(milliseconds: 650);
const _exitDuration = Duration(milliseconds: 420);
const _handleTravel = 1.0;

final _handleSpring = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 350),
    bounce: 0.55,
  ),
  seconds: 0.65,
);
