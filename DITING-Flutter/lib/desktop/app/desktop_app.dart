import 'package:diting/app/theme/colors.dart';
import 'package:diting/desktop/app/desktop_router.dart';
import 'package:diting/desktop/state/desktop_providers.dart';
import 'package:diting/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DitingDesktopApp extends ConsumerStatefulWidget {
  const DitingDesktopApp({super.key, this.initialLocation});

  final String? initialLocation;

  @override
  ConsumerState<DitingDesktopApp> createState() => _DitingDesktopAppState();
}

class _DitingDesktopAppState extends ConsumerState<DitingDesktopApp> {
  late final GoRouter _router = createDesktopRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(desktopThemeModeProvider);
    final palette = ref.watch(desktopPaletteProvider);
    return MaterialApp.router(
      title: '谛听 DNS',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppL10n.supportedLocales,
      localizationsDelegates: const [
        AppL10n.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      themeMode: switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      theme: _desktopTheme(palette.effectiveSeed, Brightness.light),
      darkTheme: _desktopTheme(palette.effectiveSeed, Brightness.dark),
    );
  }
}

ThemeData _desktopTheme(Color seedColor, Brightness brightness) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ),
  );
  final textTheme = base.textTheme;
  return base.copyWith(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textTheme: textTheme.copyWith(
      headlineLarge: textTheme.headlineLarge?.copyWith(fontSize: 32),
      headlineMedium: textTheme.headlineMedium?.copyWith(fontSize: 26),
      titleLarge: textTheme.titleLarge?.copyWith(fontSize: 20),
      titleMedium: textTheme.titleMedium?.copyWith(fontSize: 16),
      titleSmall: textTheme.titleSmall?.copyWith(fontSize: 14),
      bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.55),
      bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
      bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.5),
      labelLarge: textTheme.labelLarge?.copyWith(fontSize: 14),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thumbVisibility: const WidgetStatePropertyAll(false),
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(8),
    ),
  );
}
