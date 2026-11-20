import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

enum DashboardDensity {
  standard,
  compact,
  mobile;

  bool get isDesktop => this != mobile;

  bool get isCompact => this == compact;

  static DashboardDensity of(Size size) {
    if (size.width < minDesktopWidth) {
      return mobile;
    }
    return size.height < minStandardHeight ? compact : standard;
  }
}

const minDesktopWidth = 640.0;

const minTwoColumnWidth = 760.0;
const minStandardHeight = 824.0;
const mobileMaxWidth = 560.0;

int dashboardColumnsOf(double width) => width < minTwoColumnWidth ? 1 : 2;

double dashboardMobileSideOf(double width) =>
    math.max(16, (width - mobileMaxWidth) / 2);

class DashboardDensityScope extends InheritedWidget {
  const DashboardDensityScope({
    super.key,
    required this.density,
    required this.scale,
    required super.child,
  });

  final DashboardDensity density;
  final double scale;

  static DashboardDensityScope? _maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardDensityScope>();

  static DashboardDensity of(BuildContext context) =>
      _maybeOf(context)?.density ?? DashboardDensity.mobile;

  static double scaleOf(BuildContext context) => _maybeOf(context)?.scale ?? 1;

  @override
  bool updateShouldNotify(DashboardDensityScope oldWidget) =>
      density != oldWidget.density || scale != oldWidget.scale;
}

class DashboardDensityScopeHost extends StatelessWidget {
  const DashboardDensityScopeHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );
        return DashboardDensityScope(
          density: DashboardDensity.of(size),
          scale: MediaQuery.textScalerOf(context).scale(1),
          child: child,
        );
      },
    );
  }
}
