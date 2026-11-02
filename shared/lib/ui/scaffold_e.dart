// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'scaffold.dart';

/// The search button of a bar's button group, which gives its place up while
/// the search is open.
class _SearchLead extends StatelessWidget {
  const _SearchLead({super.key, required this.motion, required this.child});

  final _SearchMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: motion.listenable,
      builder: (_, child) {
        final frame = motion.frame;
        return ClipRect(
          clipBehavior: frame.slotCollapse > 0 ? Clip.hardEdge : Clip.none,
          child: Align(
            widthFactor: 1 - frame.slotCollapse,
            heightFactor: 1,
            child: _blurredIn(frame.glyphOpacity, child),
          ),
        );
      },
      child: child,
    );
  }
}

/// A button a bar's search grows from or into, swelling as a press does.
class _SearchSwell extends StatelessWidget {
  const _SearchSwell({
    required this.motion,
    required this.width,
    this.slotWidth = 0,
    this.droplet,
    required this.liftOf,
    required this.child,
  });

  final _SearchMotion motion;
  final double width;
  final double slotWidth;

  /// Where a lone button re-forms out of a droplet from.
  final ValueListenable<_SearchOrigin?>? droplet;
  final double Function(_SearchFrame frame) liftOf;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final droplet = this.droplet;
    return AnimatedBuilder(
      animation: Listenable.merge([motion.listenable, ?droplet]),
      builder: (_, child) {
        final frame = motion.frame;
        final width = this.width - slotWidth * frame.slotCollapse;
        final origin = droplet?.value;
        final scale =
            (1 + liftOf(frame) * ElasticPress.growthOf(width)) *
            (origin == null ? 1 : frame.dropletSize);
        final shift = origin == null
            ? 0.0
            : origin.toField * frame.dropletOffset;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(shift, 0, 0)
            ..scaleByDouble(scale, scale, 1, 1),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// The glyph of a lone search button, which fades back in as it re-forms.
class _SearchGlyph extends StatelessWidget {
  const _SearchGlyph({required this.motion, required this.child});

  final _SearchMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: motion.listenable,
      builder: (_, child) => _blurredIn(motion.frame.glyphOpacity, child),
      child: child,
    );
  }
}

/// What a bar's search covers: faded out as the field opens over it, and out
/// of reach while it is open.
class _UnderBarSearch extends StatelessWidget {
  const _UnderBarSearch({
    required this.opacity,
    required this.searching,
    required this.child,
  });

  final Animation<double> opacity;
  final bool searching;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: ExcludeFocus(
        excluding: searching,
        child: ExcludeSemantics(
          excluding: searching,
          child: IgnorePointer(ignoring: searching, child: child),
        ),
      ),
    );
  }
}

/// The field a bar's search button opens into, grown out of that button on
/// [motion]: across the bar to a [cancel] button where there is one, as iOS
/// 27 opens one over a page above a tab bar, else at the bar's end, as iPadOS
/// does. The [actions] that still apply while searching lead the field. The
/// buttons beside it grow out of its ends and flow into it under a press, as
/// iOS's do.
class _BarSearch extends StatelessWidget {
  const _BarSearch({
    required this.motion,
    required this.opacity,
    required this.origin,
    required this.fieldKey,
    required this.searching,
    required this.actions,
    required this.actionsWidth,
    required this.cancel,
    required this.glass,
    required this.color,
    required this.field,
  });

  final _SearchMotion motion;
  final Animation<double> opacity;
  final ValueListenable<_SearchOrigin?> origin;
  final GlobalKey fieldKey;
  final bool searching;
  final List<Widget> actions;
  final double actionsWidth;
  final Widget? cancel;
  final LiquidGlassStyle? glass;
  final Color color;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final cancel = this.cancel;
    final inset = appBarActionInset(cancel != null);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final height = TonalButtonSize.bar.button;
    final glyph = GlyphIcon(
      AppGlyphs.search,
      fill: 1,
      size: TonalButtonSize.bar.icon,
      color: context.colorScheme.onSurface,
    );
    return ExcludeFocus(
      excluding: !searching,
      child: IgnorePointer(
        ignoring: !searching,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final top =
                constraints.maxHeight - (pageToolbarHeight + height) / 2;
            final start = (rtl ? padding.right : padding.left) + inset;
            final end = width - (rtl ? padding.left : padding.right) - inset;
            final actionsRoom = actionsWidth > 0
                ? actionsWidth + _searchFieldGap
                : 0.0;
            final fieldEnd = cancel == null
                ? end
                : end - height - _searchFieldGap;
            final fieldStart = cancel == null
                ? math.max(start + actionsRoom, end - _regularSearchWidth)
                : start + actionsRoom;
            final actionsStart = fieldStart - actionsRoom;
            Rect place(double from, double to) => Rect.fromLTRB(
              rtl ? width - to : from,
              top,
              rtl ? width - from : to,
              top + height,
            );
            final slot = place(fieldStart, math.max(fieldStart, fieldEnd));
            final actionsRect = place(
              actionsStart,
              actionsStart + actionsWidth,
            );
            final search = AnimatedBuilder(
              animation: Listenable.merge([motion.listenable, origin]),
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                minWidth: slot.width,
                maxWidth: slot.width,
                child: field,
              ),
              builder: (_, content) {
                if (!searching && !motion.isAnimating) {
                  return const SizedBox.shrink();
                }
                final frame = motion.frame;
                final growth = frame.fieldGrowth;
                final grown = math.max(0.0, growth);
                final measured = origin.value;
                final group =
                    measured?.at(frame.slotCollapse) ??
                    place(fieldEnd - height, fieldEnd);
                final leading = cancel == null ? null : measured?.leading;
                final from = leading == null
                    ? group
                    : Rect.lerp(group, leading, frame.towardLeading)!;
                final fieldRect = _lifted(
                  Rect.lerp(from, slot, growth)!,
                  frame.glassLift + frame.fieldSwell,
                );
                Widget grow(
                  Rect rest,
                  Widget child, {
                  required bool leads,
                  Rect? home,
                }) {
                  final facesRight = leads != rtl;
                  final reach = lerpDouble(
                    height / 2,
                    -_searchFieldGap,
                    grown,
                  )!;
                  final anchor = facesRight
                      ? fieldRect.left + reach
                      : fieldRect.right - reach;
                  final size = rest.size * grown;
                  var rect = Rect.fromLTWH(
                    facesRight ? anchor - size.width : anchor,
                    rest.center.dy - size.height / 2,
                    size.width,
                    size.height,
                  );
                  if (home != null) {
                    rect = Rect.lerp(
                      rect,
                      Rect.lerp(home, rest, grown),
                      frame.towardLeading,
                    )!;
                  }
                  rect = _lifted(rect, frame.glassLift);
                  rect = Rect.fromCenter(
                    center: rect.center,
                    width: rect.width * frame.flankScale,
                    height: rect.height * frame.flankScale,
                  );
                  final scale = rect.width / rest.width;
                  return Positioned.fromRect(
                    rect: rest,
                    child: Transform(
                      transform: Matrix4.translationValues(
                        rect.left - rest.left,
                        rect.top - rest.top,
                        0,
                      )..scaleByDouble(scale, scale, 1, 1),
                      child: _blurredIn(frame.flankOpacity, child),
                    ),
                  );
                }

                return TextFieldTapRegion(
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: fieldRect,
                        child: ElasticPress(
                          key: fieldKey,
                          child: GooPane(
                            child: ClipRSuperellipse(
                              borderRadius: AppRadius.full,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  _blurredIn(frame.contentOpacity, content),
                                  if (frame.fieldGlyphOpacity > 0)
                                    _blurredIn(frame.fieldGlyphOpacity, glyph),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (actions.isNotEmpty)
                        grow(
                          actionsRect,
                          Row(
                            children: [
                              ...actions.separated(
                                const SizedBox(width: _barButtonGap),
                              ),
                            ],
                          ),
                          leads: true,
                        ),
                      if (cancel != null)
                        grow(
                          place(end - height, end),
                          cancel,
                          leads: false,
                          home: leading == null
                              ? null
                              : measured?.withoutSearch,
                        ),
                    ],
                  ),
                );
              },
            );
            return LiquidGlassFade(
              opacity: opacity,
              child: GooSurface(
                glass: glass,
                color: color,
                child: TonalButtonTheme(glass: glass != null, child: search),
              ),
            );
          },
        ),
      ),
    );
  }
}
