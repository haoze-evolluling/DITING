// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/button.dart';
import 'package:diting_shared/ui/focus.dart';
import 'package:diting_shared/ui/goo.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:diting_shared/ui/l10n.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/support/input_limits.dart';
import 'package:diting_shared/ui/surface.dart';
import 'package:diting_shared/ui/typography.dart';
import 'package:material_ui/material_ui.dart';

const sheetSearchMinItemCount = 10;

const double _glyphInset = 12;
const double _textInset = 41;
const double _clearReach = 49;
const double _clearSize = 24;

class SearchField extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final double? height;
  final Color? fill;
  final IconData glyph;
  final String? hintText;
  final VoidCallback? onSubmitted;
  final Widget? trailing;

  const SearchField({
    super.key,
    this.onChanged,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.height,
    this.fill,
    this.glyph = TablerIcons.search,
    this.hintText,
    this.onSubmitted,
    this.trailing,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  TextEditingController? _ownedController;

  TextEditingController get _controller =>
      widget.controller ?? (_ownedController ??= TextEditingController());

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  void _handleClear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final localizations = UiLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final remote = RemoteFocusAdapter.isEnabledOf(context);
    final pill = AppShape.input.copyWith(borderRadius: AppRadius.standard);
    final trailing = widget.trailing;
    final fill =
        widget.fill ??
        (GooSurface.of(context)
            ? null
            : context.raisedSurfaceLevel.colorOf(colorScheme));
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, FocusMovedByKey.instance]),
      builder: (_, _) {
        final empty = _controller.text.isEmpty;
        final ringed = remote || FocusMovedByKey.instance.value;
        return TextField(
          controller: _controller,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          maxLines: 1,
          textAlignVertical: TextAlignVertical.center,
          textInputAction: TextInputAction.search,
          style: AppTextRole.body.of(context),
          inputFormatters: TextInputLimits.limit(TextInputLimits.search),
          onChanged: widget.onChanged,
          onSubmitted: (_) => widget.onSubmitted?.call(),
          decoration: InputDecoration(
            constraints: BoxConstraints.tightFor(
              height: widget.height ?? TonalButtonSize.bar.button,
            ),
            floatingLabelBehavior: FloatingLabelBehavior.never,
            filled: fill != null,
            fillColor: fill,
            hintText: widget.hintText ?? localizations.search,
            border: pill.copyWith(borderSide: BorderSide.none),
            enabledBorder: pill.copyWith(borderSide: BorderSide.none),
            focusedBorder: pill.copyWith(
              borderSide: ringed ? focusRingSide(colorScheme) : BorderSide.none,
            ),
            contentPadding: EdgeInsetsDirectional.only(
              end: empty && trailing == null ? 12 : 0,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(start: _glyphInset),
              child: Icon(widget.glyph, size: 20),
            ),
            prefixIconConstraints: const BoxConstraints.tightFor(
              width: _textInset,
            ),
            suffixIcon: empty && trailing == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?trailing,
                      if (!empty)
                        SizedBox(
                          width: _clearReach,
                          child: IconButton(
                            tooltip: localizations.clearSearch,
                            onPressed: _handleClear,
                            style: IconButton.styleFrom(
                              foregroundColor: colorScheme.onSurface,
                              overlayColor: Colors.transparent,
                              splashFactory: NoSplash.splashFactory,
                            ),
                            icon: const Icon(
                              TablerIcons.circle_x_filled,
                              size: _clearSize,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 8),
                    ],
                  ),
            suffixIconConstraints: const BoxConstraints(),
          ),
        );
      },
    );
  }
}
