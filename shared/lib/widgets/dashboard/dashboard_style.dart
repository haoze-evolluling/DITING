import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Dashboard palette, after upstream views/dashboard/style.dart.
class DashboardColors {
  const DashboardColors._({
    required this.page,
    required this.card,
    required this.tone,
    required this.tone2,
    required this.track,
    required this.series2,
    required this.ok,
    required this.warn,
  });

  factory DashboardColors.of(BuildContext context) {
    final colorScheme = context.colorScheme;
    final card = SurfaceLevel.card.colorOf(colorScheme);
    return DashboardColors._(
      page: SurfaceLevel.page.colorOf(colorScheme),
      card: card,
      tone: SurfaceLevel.block.colorOf(colorScheme),
      tone2: SurfaceLevel.inset.colorOf(colorScheme),
      track: colorScheme.surfaceContainerHighest,
      // Upload curve: primary mixed 45% with the card color, distinct but same family.
      series2: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.45),
        card,
      ),
      ok: colorScheme.success,
      warn: colorScheme.warning,
    );
  }

  final Color page;
  final Color card;
  final Color tone;
  final Color tone2;
  final Color track;
  final Color series2;
  final Color ok;
  final Color warn;
}

/// Elevation shadows. Design values are CSS `blur`, twice Flutter's blurRadius (Flutter
/// maps radius r to sigma = 0.577r + 0.5), so every value goes through [blur].
abstract final class DashboardShadows {
  static List<BoxShadow> e1(BuildContext context) =>
      context.colorScheme.brightness == Brightness.dark ? _e1Dark : _e1Light;

  static List<BoxShadow> e2(BuildContext context) =>
      context.colorScheme.brightness == Brightness.dark ? _e2Dark : _e2Light;

  static BoxShadow _shadow(
    int alpha,
    double y,
    double cssBlur, [
    double spread = 0,
  ]) => BoxShadow(
    color: Color.fromARGB(alpha, 0, 0, 0),
    offset: Offset(0, y),
    blurRadius: blur(cssBlur),
    spreadRadius: spread,
  );

  static double blur(double cssBlur) =>
      cssBlur <= 1 ? 0 : (cssBlur / 2 - 0.5) / 0.57735;

  static final _e1Light = [
    _shadow(0x0D, 0.5, 1),
    _shadow(0x0A, 2, 6),
    _shadow(0x17, 12, 32, -6),
  ];

  static final _e1Dark = [_shadow(0x80, 1, 2), _shadow(0x8C, 10, 28, -6)];

  static final _e2Light = [
    _shadow(0x0F, 1, 3),
    _shadow(0x14, 10, 24),
    _shadow(0x38, 32, 64, -12),
  ];

  static final _e2Dark = [_shadow(0x80, 2, 6), _shadow(0xB3, 32, 64, -12)];
}

/// Corner radii. Larger than AppCorner: the dashboard card sits above every other surface.
///
/// Desktop cards are 24 rather than the mobile 34: a window shows several of them at once, and a
/// card that round reads as a phone widget. The inner block steps down twice so a tile inside a
/// card never looks like it shares the card's own corner.
abstract final class DashboardCorner {
  static const desktopCard = 24.0;
  static const mobileCard = 34.0;
  static const block = 14.0;
  static const mobileBlock = 22.0;
  static const tab = 16.0;
  static const badge = 14.0;
}

/// Dashboard text roles. All figures use tabular digits so rows do not jitter.
///
/// A desktop card is read from a distance: its title has to sit clearly above the note under it,
/// which is why the desktop pair is 15/13 rather than the phone's 15/12. The phone keeps its own
/// sizes so its cards do not lose five lines to a taller note.
abstract final class DashboardText {
  static bool _desktop(BuildContext context) =>
      DashboardDensityScope.of(context).isDesktop;

  /// The card's own name. Full-strength ink: on a desktop card the title, the note under it and
  /// the figures all used to sit in the same grey, which left the card without a first line.
  static TextStyle cardTitle(BuildContext context) =>
      AppTextStyle.subheadline.of(context, emphasized: true).copyWith(
        color: context.colorScheme.onSurface,
      );

  static TextStyle label(BuildContext context, {Color? color}) =>
      (_desktop(context) ? AppTextStyle.footnote : AppTextStyle.caption1)
          .of(context)
          .toTabular
          .copyWith(
            color: color ?? context.colorScheme.onSurfaceVariant,
            // A desktop note often wraps to two lines; 13 px text needs more air between them
            // than the phone's 12 px single-line captions do.
            height: _desktop(context) ? 1.45 : null,
          );

  static TextStyle figure(
    BuildContext context,
    AppTextStyle style, {
    Color? color,
  }) => style
      .of(context, emphasized: true)
      .toTabular
      .copyWith(color: color, letterSpacing: -0.02 * style.size);

  static TextStyle unit(
    BuildContext context, [
    AppTextStyle style = AppTextStyle.subheadline,
  ]) => style
      .of(context, emphasized: true)
      .copyWith(color: context.colorScheme.onSurfaceVariant);

  static TextStyle rowTitle(BuildContext context) =>
      AppTextStyle.subheadline.of(context, emphasized: true);
}

EdgeInsets dashboardCardPadding(DashboardDensity density) => switch (density) {
  DashboardDensity.standard => const EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 22,
  ),
  DashboardDensity.compact => const EdgeInsets.symmetric(
    horizontal: 22,
    vertical: 20,
  ),
  DashboardDensity.mobile => const EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 18,
  ),
};

/// Vertical gap between dashboard cards; the gap comes from the enclosing
/// Column(spacing:). Wide enough that two 24-radius corners never read as one shape.
const double dashboardCardGap = 16;

double dashboardCardRadius(DashboardDensity density) => density.isDesktop
    ? DashboardCorner.desktopCard
    : DashboardCorner.mobileCard;

/// Bytes to `1.2 MB`, base 1000 to match the traffic page.
String dashboardTraffic(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// Count with thousands separators; above 100k switches to compact form so it
/// does not overflow a narrow card.
String dashboardCount(int count) {
  if (count >= 100000) {
    return '${(count / 1000).toStringAsFixed(0)}k';
  }
  final digits = count.abs().toString();
  final buffer = StringBuffer(count < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Speed text, e.g. `12.3 KB/s`.
String dashboardSpeed(num bytesPerSecond) =>
    '${dashboardTraffic(bytesPerSecond)}/s';
