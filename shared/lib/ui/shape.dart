// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:math' as math;
import 'dart:ui' show ClipOp, lerpDouble;

import 'package:material_ui/material_ui.dart';

/// The single corner-radius standard for the whole product.
///
/// Every rounded surface — cards, sheets, dialogs, inputs, popups, chips,
/// buttons, badges, avatars, switches, progress bars — must reference
/// [AppCorner.standard] directly, or through [AppRadius.standard] /
/// [AppShape.standard]. Changing this one constant restyles the entire app.
///
/// [none] (0) is the only other permitted value, reserved for structural edges
/// that must stay square: a sheet flush with the screen edge, or the inner edge
/// of a grouped list where only the first/last row rounds.
abstract final class AppCorner {
  /// The one standard corner radius, in logical pixels.
  static const double standard = 20;

  /// No rounding. Reserved for structural edges that must stay square.
  static const double none = 0;
}

abstract final class AppRadius {
  /// The standard [BorderRadius] (all corners at [AppCorner.standard]).
  static const BorderRadius standard = BorderRadius.all(
    Radius.circular(AppCorner.standard),
  );

  /// Square corners for structural edges only.
  static const BorderRadius none = BorderRadius.zero;

  static BorderRadius all(double corner) => BorderRadius.circular(corner);

  static BorderRadius top(double corner) =>
      BorderRadius.vertical(top: Radius.circular(corner));

  static BorderRadius vertical({
    double top = AppCorner.none,
    double bottom = AppCorner.none,
  }) => BorderRadius.vertical(
    top: Radius.circular(top),
    bottom: Radius.circular(bottom),
  );
}

abstract final class AppShape {
  /// The standard superellipse shape (all corners at [AppCorner.standard]).
  static const RoundedSuperellipseBorder standard = RoundedSuperellipseBorder(
    borderRadius: AppRadius.standard,
  );

  /// Square corners for structural edges only.
  static const RoundedSuperellipseBorder none = RoundedSuperellipseBorder();

  static const AppInputBorder input = AppInputBorder();

  static RoundedSuperellipseBorder all(double corner) =>
      RoundedSuperellipseBorder(borderRadius: AppRadius.all(corner));

  static RoundedSuperellipseBorder top(double corner) =>
      RoundedSuperellipseBorder(borderRadius: AppRadius.top(corner));

  static RoundedSuperellipseBorder vertical({
    double top = AppCorner.none,
    double bottom = AppCorner.none,
  }) => RoundedSuperellipseBorder(
    borderRadius: AppRadius.vertical(top: top, bottom: bottom),
  );

  static RoundedSuperellipseBorder of(BorderRadius borderRadius) =>
      RoundedSuperellipseBorder(borderRadius: borderRadius);
}

class AppInputBorder extends InputBorder {
  const AppInputBorder({
    super.borderSide = const BorderSide(),
    this.borderRadius = AppRadius.standard,
    this.gapPadding = 4.0,
  });

  final BorderRadius borderRadius;
  final double gapPadding;

  RoundedSuperellipseBorder get _shape =>
      RoundedSuperellipseBorder(borderRadius: borderRadius, side: borderSide);

  @override
  bool get isOutline => true;

  @override
  bool get preferPaintInterior => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  AppInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) {
    return AppInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
    );
  }

  @override
  AppInputBorder scale(double t) {
    return AppInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      gapPadding: gapPadding * t,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect, textDirection: textDirection);

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => _shape.paintInterior(canvas, rect, paint, textDirection: textDirection);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is AppInputBorder) {
      return AppInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: a.gapPadding,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is AppInputBorder) {
      return AppInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        gapPadding: b.gapPadding,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final outline = rect.deflate(borderSide.width / 2);
    if (gapStart == null || gapExtent <= 0.0 || gapPercentage == 0.0) {
      _shape.paint(canvas, rect, textDirection: textDirection);
      return;
    }
    final extent = lerpDouble(
      0.0,
      gapExtent + gapPadding * 2.0,
      gapPercentage,
    )!;
    final start = switch (textDirection ?? TextDirection.ltr) {
      TextDirection.rtl => gapStart + gapPadding - extent,
      TextDirection.ltr => gapStart - gapPadding,
    };
    final radii = borderRadius.resolve(textDirection);
    final left = outline.left + math.max(0.0, start);
    final depth =
        math.max(radii.topLeft.y, radii.topRight.y) + borderSide.width;
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTRB(
          left,
          outline.top - borderSide.width,
          left + extent,
          outline.top + depth,
        ),
        clipOp: ClipOp.difference,
      );
    _shape.paint(canvas, rect, textDirection: textDirection);
    canvas.restore();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppInputBorder &&
        other.borderSide == borderSide &&
        other.borderRadius == borderRadius &&
        other.gapPadding == gapPadding;
  }

  @override
  int get hashCode => Object.hash(borderSide, borderRadius, gapPadding);
}

extension AppShapeThemeExt on ThemeData {
  ThemeData get withAppShapes => copyWith(
    cardTheme: cardTheme.copyWith(shape: AppShape.standard),
    dialogTheme: dialogTheme.copyWith(shape: AppShape.standard),
    // A bottom sheet is flush with the bottom edge, so only its top corners round.
    bottomSheetTheme: bottomSheetTheme.copyWith(
      shape: AppShape.top(AppCorner.standard),
    ),
    snackBarTheme: snackBarTheme.copyWith(shape: AppShape.standard),
    tooltipTheme: tooltipTheme.copyWith(
      // A decoration replaces Material's tooltip colours too, so restate them.
      decoration: ShapeDecoration(
        shape: AppShape.standard,
        color: switch (brightness) {
          Brightness.dark => Colors.white.withAlpha(230),
          Brightness.light => Colors.grey[700]!.withAlpha(230),
        },
      ),
    ),
    chipTheme: chipTheme.copyWith(shape: AppShape.standard),
    popupMenuTheme: popupMenuTheme.copyWith(shape: AppShape.standard),
    menuTheme: MenuThemeData(
      style: (menuTheme.style ?? const MenuStyle()).copyWith(
        shape: const WidgetStatePropertyAll(AppShape.standard),
      ),
    ),
    inputDecorationTheme: inputDecorationTheme.copyWith(
      border: AppShape.input,
      // A helper line explains the format of a field ("每行一个 IP") and is often a full sentence;
      // at one line it was cut with an ellipsis on every form that used it.
      helperMaxLines: 2,
      errorMaxLines: 2,
    ),
    floatingActionButtonTheme: floatingActionButtonTheme.copyWith(
      shape: AppShape.standard,
    ),
    navigationBarTheme: navigationBarTheme.copyWith(
      indicatorShape: AppShape.standard,
    ),
    navigationRailTheme: navigationRailTheme.copyWith(
      indicatorShape: AppShape.standard,
    ),
    progressIndicatorTheme: progressIndicatorTheme.copyWith(
      borderRadius: AppRadius.standard,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: filledButtonTheme.style?.merge(_standardButton) ?? _standardButton,
    ),
    textButtonTheme: TextButtonThemeData(
      style: textButtonTheme.style?.merge(_standardButton) ?? _standardButton,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          outlinedButtonTheme.style?.merge(_standardButton) ?? _standardButton,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style:
          elevatedButtonTheme.style?.merge(_standardButton) ?? _standardButton,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: iconButtonTheme.style?.merge(_standardButton) ?? _standardButton,
    ),
  );
}

const _standardButton = ButtonStyle(
  shape: WidgetStatePropertyAll(AppShape.standard),
);
