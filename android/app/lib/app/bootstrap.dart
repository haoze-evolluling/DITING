import 'package:diting_android/app/theme/layout.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class AppScopes extends StatelessWidget {
  const AppScopes({super.key, required this.child, this.textScale = 1});

  final Widget child;

  final double textScale;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final scale = clampTextScale(textScale * mediaQuery.textScaler.scale(1));
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(scale),
        viewPadding: mediaQuery.viewPadding,
      ),
      child: MeasureScope(
        measure: Measure.of(context, scale),
        child: ViewScope(
          size: size,
          isMobile: isMobileWidth(size.width),
          child: child,
        ),
      ),
    );
  }
}

class AppSystemUi extends StatefulWidget {
  const AppSystemUi({super.key, required this.child});

  final Widget child;

  @override
  State<AppSystemUi> createState() => _AppSystemUiState();
}

class _AppSystemUiState extends State<AppSystemUi> {
  Brightness? _applied;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness != _applied) {
      _applied = brightness;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        SystemChrome.setSystemUIOverlayStyle(
          brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
        );
      });
    }
    return widget.child;
  }
}
