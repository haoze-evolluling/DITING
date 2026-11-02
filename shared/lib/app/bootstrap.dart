import 'package:diting_shared/app/theme/layout.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The scopes `lib/ui` asserts on. Vendored components resolve `MeasureScope`, `ViewScope`
/// and `UiLocalizations` via `assert(scope != null)`; overlay helpers push on the nearest
/// `Navigator`, whose context is a child of it, so `MaterialApp.builder` suits both.
class AppScopes extends StatelessWidget {
  const AppScopes({super.key, required this.child, this.textScale = 1});

  final Widget child;

  /// Linear text scale from settings, clamped to [minTextScale]-[maxTextScale] and then by
  /// the platform accessibility setting.
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final scale = clampTextScale(textScale * mediaQuery.textScaler.scale(1));
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(scale),
        // The dock draws its own bottom margin; the framework inset would double it.
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

/// Applies the status-bar overlay style the current theme asks for. `MaterialApp` would do
/// this itself, but [ThemeCrossFade] keeps the resolved theme out of its reach.
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
