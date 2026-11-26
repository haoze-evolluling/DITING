import 'package:diting_android/widgets/dashboard/dashboard_density.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

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

abstract final class DashboardShadows {
  static List<BoxShadow> e1(BuildContext context) =>
      context.colorScheme.brightness == Brightness.dark ? _e1Dark : _e1Light;

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
}

abstract final class DashboardText {
  static TextStyle cardTitle(BuildContext context) =>
      AppTextRole.cardTitle.of(context);

  static TextStyle label(BuildContext context, {Color? color}) => AppTextRole
      .supportingText
      .of(context)
      .toTabular
      .copyWith(color: color ?? context.colorScheme.onSurfaceVariant);

  static TextStyle figure(
    BuildContext context,
    AppTextRole style, {
    Color? color,
  }) => style.of(context).toTabular.copyWith(color: color);

  static TextStyle unit(
    BuildContext context, [
    AppTextRole style = AppTextRole.metricUnit,
  ]) => style.of(context);

  static TextStyle rowTitle(BuildContext context) =>
      AppTextRole.rowTitle.of(context);
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

const double dashboardCardGap = 16;

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
