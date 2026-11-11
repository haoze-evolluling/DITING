import 'dart:math' as math;

import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

part 'dashboard_connected_buttons.dart';

/// Dashboard card, after upstream views/dashboard/widgets/card.dart. Adds elevation tiers
/// and a larger radius than [CommonCard]: 32+ here against 16-20 for list cards.
class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    this.padding,
    this.onTap,
    this.semanticLabel,
    this.clipBehavior = Clip.none,
    required this.child,
  });

  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Not clipped by default so a pressed control can spill over the edge; only
  /// charts, whose content can overflow, opt in.
  final Clip clipBehavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final shape = AppShape.all(dashboardCardRadius(density));
    final editBar = DashboardEditBar.of(context);
    // Each card owns its own layer: the 1 s speed/traffic and 2 s memory figures rebuild a single
    // card, and without a boundary here that dirty child promotes the whole scroll body (every card
    // and its shadow) into one full-width repaint, which is what dropped a frame mid-fling. The
    // decoration above this boundary stays cached, so the shadow is not re-rastered either.
    final content = RepaintBoundary(
      child: Padding(
        padding: padding ?? dashboardCardPadding(density),
        child: editBar == null
            ? child
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: DashboardEditBar.height, child: editBar),
                  const SizedBox(height: DashboardEditBar.gap),
                  // Dim the body only, so the edit bar keeps its colors. Editing wins over the
                  // card's own buttons: a tap mid-arrangement would read as a lost drag.
                  IgnorePointer(child: DisabledMask(status: true, child: child)),
                ],
              ),
      ),
    );
    // The card is its own surface level: anything nested (a `CommonCard` tile, a chip) must be
    // painted one level up, otherwise it takes the card's own color and its background vanishes.
    final scoped = SurfaceScope(level: SurfaceLevel.card, child: content);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        clipBehavior: clipBehavior,
        decoration: ShapeDecoration(
          color: DashboardColors.of(context).card,
          shape: shape,
          shadows: DashboardShadows.e1(context),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: onTap == null || editBar != null
              ? scoped
              : FocusRing(
                  shape: shape,
                  child: InkWell(
                    customBorder: shape,
                    onTap: onTap,
                    child: scoped,
                  ),
                ),
        ),
      ),
    );
  }
}

/// `DashboardCard` reserves a row for the bar above its content.
class DashboardEditBar extends InheritedWidget {
  const DashboardEditBar({super.key, required this.bar, required super.child});

  static const height = 28.0;
  static const gap = 10.0;

  final Widget bar;

  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardEditBar>()?.bar;

  @override
  bool updateShouldNotify(DashboardEditBar oldWidget) => bar != oldWidget.bar;
}

/// Card title row: icon, title, trailing action. Height 24 is the design value.
class DashboardCardHeader extends StatelessWidget {
  const DashboardCardHeader({
    super.key,
    this.glyph,
    required this.title,
    this.leading = const [],
    this.trailing = const [],
    this.chevron = false,
  });

  static const height = 24.0;
  static const glyphSize = 18.0;

  final Glyph? glyph;
  final String title;

  final List<Widget> leading;
  final List<Widget> trailing;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final style = DashboardText.cardTitle(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: Row(
        spacing: 8,
        children: [
          if (glyph case final glyph?)
            GlyphIcon(
              glyph,
              size: glyphSize,
              color: colorScheme.onSurfaceVariant,
            ),
          // The title and its badges flow: a title is never cut to make room for a status
          // chip, the chip moves under it instead. A badge carries a secondary fact, so it
          // must not decide how much of the name the reader gets.
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
                ...leading,
              ],
            ),
          ),
          // A trailing control keeps the title row's own height instead of growing with a
          // badge that wrapped: the switch stays a switch, and its overflow box still has a
          // bounded box to center in.
          for (final child in trailing)
            SizedBox(height: height, child: Center(child: child)),
          if (chevron)
            GlyphIcon(
              AppGlyphs.chevronForward,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),        ],
      ),
    );
  }
}

class DashboardBlock extends StatelessWidget {
  const DashboardBlock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: color ?? DashboardColors.of(context).tone,
        shape: AppShape.all(
          density.isDesktop
              ? DashboardCorner.block
              : DashboardCorner.mobileBlock,
        ),
      ),
      child: child,
    );
  }
}

enum DashboardChipTone { idle, ok, warn }

/// Status badge. [dot] adds a leading dot, [large] is used next to titles.
class DashboardChip extends StatelessWidget {
  const DashboardChip({
    super.key,
    required this.label,
    this.tone = DashboardChipTone.idle,
    this.dot = false,
    this.large = false,
  });

  final String label;
  final DashboardChipTone tone;
  final bool dot;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final (foreground, background) = switch (tone) {
      DashboardChipTone.idle => (colorScheme.onSurfaceVariant, colors.tone),
      DashboardChipTone.ok => (colorScheme.success, colors.tone),
      DashboardChipTone.warn => (colorScheme.warning, colors.tone),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 8,
        vertical: large ? 5 : 3,
      ),
      decoration: ShapeDecoration(
        color: background,
        shape: AppShape.all(AppCorner.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          if (dot)
            Container(
              width: 6,
              height: 6,
              decoration: ShapeDecoration(
                color: foreground,
                shape: const CircleBorder(),
              ),
            ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (large ? AppTextStyle.footnote : AppTextStyle.caption1)
                  .of(context, emphasized: true)
                  .toTabular
                  .copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// One `label : value` row. Both texts ellipsize and the row is unfixed, so `1.2 GB`
/// truncates on a 320dp row.
class DashboardMetric extends StatelessWidget {
  const DashboardMetric({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.style = AppTextStyle.headline,
  });

  final String label;
  final String value;
  final Color? color;

  /// The figure's role: [AppTextStyle.title2] for a card's headline number, the default
  /// headline for the figures of a grid.
  final AppTextStyle style;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.figure(context, style, color: color),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
      ],
    );
  }
}

/// A grid of [DashboardMetric]s in equal-width cells.
///
/// Up to [maxColumns] per row, and never fewer than two when the text is scaled up: four figures
/// side by side at 1.4x are ellipsized to `12,...`, which is worse than taking two rows.
class DashboardMetricGrid extends StatelessWidget {
  const DashboardMetricGrid({
    super.key,
    required this.metrics,
    this.maxColumns = 4,
    this.gap = 16,
    this.runGap = 14,
  });

  final List<DashboardMetric> metrics;

  /// Columns at the normal text size; a narrow card simply uses as many as there are metrics.
  final int maxColumns;

  final double gap;
  final double runGap;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final columns = scale >= 1.2 ? math.min(2, maxColumns) : maxColumns;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = math.max(1, math.min(columns, metrics.length));
        final cellWidth = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: runGap,
          children: [
            for (final metric in metrics)
              SizedBox(width: cellWidth, child: metric),
          ],
        );
      },
    );
  }
}

/// A switch laid out at its track size, not its tap target: a 48-high target would set the height
/// of every row that holds one. The surrounding card owns the tap.
class DashboardSwitch extends StatelessWidget {
  const DashboardSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CommonSwitch.trackWidth,
      height: CommonSwitch.trackHeight,
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: CommonSwitch(
          value: value,
          onChanged: onChanged,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

/// Round icon button for the card's top-right corner. The 24-high title row would squeeze a
/// default button, so it overflows explicitly.
class DashboardIconButton extends StatelessWidget {
  const DashboardIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    this.onPressed,
    this.size = 32,
    this.glyphSize = 18,
  });

  final Glyph glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: OverflowBox(
        minHeight: size,
        maxHeight: size,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: glyphSize,
          style: IconButton.styleFrom(
            minimumSize: Size.square(size),
            fixedSize: Size.square(size),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: context.colorScheme.onSurfaceVariant,
          ),
          onPressed: onPressed,
          icon: GlyphIcon(glyph, size: glyphSize),
        ),
      ),
    );
  }
}

/// Card entrance: fade plus a small rise, played once per list refresh. Shared so the desktop
/// board animates in exactly like the Android one instead of picking its own curve.
class DashboardCardEntrance extends StatelessWidget {
  const DashboardCardEntrance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      // The card is cached behind the fade: Opacity over an un-cached subtree re-rasterises the
      // card's soft shadow on every frame of the rise, which is what made a swipe during the
      // first-run entrance stutter. A RepaintBoundary here turns each frame into a composite of
      // the already-painted card instead of another full-card paint.
      builder: (context, amount, child) => Opacity(
        opacity: amount,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - amount)),
          child: child,
        ),
      ),
      child: RepaintBoundary(child: child),
    );
  }
}
