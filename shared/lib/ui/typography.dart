// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/font.dart';
import 'package:material_ui/material_ui.dart';

/// The app's complete typographic role table.
///
/// Pages and components select a role instead of setting font sizes or line
/// heights. Mobile and desktop deltas live only in this enum.
enum AppTextRole {
  pageTitle(24, 30, weight: FontWeight.w600),
  sectionTitle(20, 26, weight: FontWeight.w600),
  cardTitle(17, 22, weight: FontWeight.w600),
  rowTitle(17, 22),
  body(15, 22, desktopSize: 16, desktopLeading: 24),
  bodyStrong(
    15,
    22,
    weight: FontWeight.w600,
    desktopSize: 16,
    desktopLeading: 24,
  ),
  bodyReading(17, 26),
  sectionLabel(13, 18, weight: FontWeight.w600, secondary: true),
  supportingText(13, 18, secondary: true),
  legalText(13, 22, secondary: true),
  caption(12, 16, secondary: true),
  micro(11, 14, secondary: true),
  metricLarge(28, 34, weight: FontWeight.w700, metric: true),
  metricMedium(22, 28, weight: FontWeight.w700, metric: true),
  metricSmall(20, 26, weight: FontWeight.w700, metric: true),
  metricCompact(17, 22, weight: FontWeight.w700, metric: true),
  metricUnit(13, 18, weight: FontWeight.w600, secondary: true, tabular: true),
  button(15, 20, weight: FontWeight.w600),
  input(17, 22),
  badge(12, 16, weight: FontWeight.w600, secondary: true, tabular: true),
  numeric(13, 18, secondary: true, tabular: true),
  code(13, 20, tabular: true),
  dockLabel(10, 14.5, weight: FontWeight.w500, secondary: true);

  const AppTextRole(
    this.size,
    this.leading, {
    this.weight = FontWeight.w400,
    this.secondary = false,
    this.desktopSize,
    this.desktopLeading,
    this.tabular = false,
    this.metric = false,
  });

  final double size;
  final double leading;
  final FontWeight weight;
  final bool secondary;
  final double? desktopSize;
  final double? desktopLeading;
  final bool tabular;
  final bool metric;

  double sizeOf(BuildContext context) =>
      _desktop(context) ? desktopSize ?? size : size;

  double leadingOf(BuildContext context) =>
      _desktop(context) ? desktopLeading ?? leading : leading;

  TextStyle of(BuildContext context) {
    final theme = Theme.of(context);
    return _style(
      _slotOf(theme.textTheme)!,
      theme.colorScheme,
      desktop: _desktop(context),
    );
  }

  TextStyle _style(
    TextStyle base,
    ColorScheme colors, {
    required bool desktop,
  }) {
    final resolvedSize = desktop ? desktopSize ?? size : size;
    final resolvedLeading = desktop ? desktopLeading ?? leading : leading;
    return base.copyWith(
      fontSize: resolvedSize,
      height: resolvedLeading / resolvedSize,
      fontWeight: weight,
      letterSpacing: metric ? -0.02 * resolvedSize : 0,
      fontFeatures: tabular || metric ? appTabularFigures : null,
      color: secondary ? colors.onSurfaceVariant : colors.onSurface,
    );
  }

  TextStyle? _on(
    TextStyle? base,
    ColorScheme colors, {
    required bool desktop,
  }) => base == null ? null : _style(base, colors, desktop: desktop);

  // Typography.blackCupertino draws these slots with SF Pro Display, the rest with SF Pro Text.
  TextStyle? _slotOf(TextTheme theme) => switch (this) {
    pageTitle => theme.headlineLarge,
    sectionTitle => theme.headlineMedium,
    cardTitle || rowTitle || input => theme.titleLarge,
    body || bodyStrong || bodyReading => theme.bodyLarge,
    sectionLabel || supportingText || legalText => theme.bodyMedium,
    caption || numeric || code => theme.bodySmall,
    micro => theme.labelSmall,
    metricLarge => theme.headlineLarge,
    metricMedium => theme.headlineMedium,
    metricSmall || metricCompact => theme.headlineSmall,
    metricUnit => theme.labelMedium,
    button => theme.labelLarge,
    badge => theme.labelMedium,
    dockLabel => theme.labelSmall,
  };
}

bool _desktop(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => true,
  TargetPlatform.android ||
  TargetPlatform.fuchsia ||
  TargetPlatform.iOS => false,
};

extension AppTypographyThemeExt on ThemeData {
  ThemeData get withAppTypography => copyWith(
    textTheme: _onAppScale(
      textTheme,
      colorScheme,
      desktop: _desktopPlatform(platform),
    ),
    primaryTextTheme: _onAppScale(
      primaryTextTheme,
      colorScheme,
      desktop: _desktopPlatform(platform),
    ),
  );
}

bool _desktopPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => true,
  TargetPlatform.android ||
  TargetPlatform.fuchsia ||
  TargetPlatform.iOS => false,
};

TextTheme _onAppScale(
  TextTheme theme,
  ColorScheme colors, {
  required bool desktop,
}) => theme.copyWith(
  displayLarge: AppTextRole.metricLarge._on(
    theme.displayLarge,
    colors,
    desktop: desktop,
  ),
  displayMedium: AppTextRole.metricLarge._on(
    theme.displayMedium,
    colors,
    desktop: desktop,
  ),
  displaySmall: AppTextRole.metricLarge._on(
    theme.displaySmall,
    colors,
    desktop: desktop,
  ),
  headlineLarge: AppTextRole.pageTitle._on(
    theme.headlineLarge,
    colors,
    desktop: desktop,
  ),
  headlineMedium: AppTextRole.sectionTitle._on(
    theme.headlineMedium,
    colors,
    desktop: desktop,
  ),
  headlineSmall: AppTextRole.sectionTitle._on(
    theme.headlineSmall,
    colors,
    desktop: desktop,
  ),
  titleLarge: AppTextRole.cardTitle._on(
    theme.titleLarge,
    colors,
    desktop: desktop,
  ),
  titleMedium: AppTextRole.rowTitle._on(
    theme.titleMedium,
    colors,
    desktop: desktop,
  ),
  titleSmall: AppTextRole.sectionLabel._on(
    theme.titleSmall,
    colors,
    desktop: desktop,
  ),
  bodyLarge: AppTextRole.body._on(theme.bodyLarge, colors, desktop: desktop),
  bodyMedium: AppTextRole.body._on(theme.bodyMedium, colors, desktop: desktop),
  bodySmall: AppTextRole.supportingText._on(
    theme.bodySmall,
    colors,
    desktop: desktop,
  ),
  labelLarge: AppTextRole.button._on(
    theme.labelLarge,
    colors,
    desktop: desktop,
  ),
  labelMedium: AppTextRole.badge._on(
    theme.labelMedium,
    colors,
    desktop: desktop,
  ),
  labelSmall: AppTextRole.micro._on(theme.labelSmall, colors, desktop: desktop),
);
