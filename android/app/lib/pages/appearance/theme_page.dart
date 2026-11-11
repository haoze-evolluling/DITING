/// Appearance settings menu, mirroring the legacy `APPEARANCE_SETTINGS`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/widgets/appearance/mini_screen.dart';
import 'package:diting_shared/widgets/appearance/theme_preview.dart';
import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/font_providers.dart';
import 'package:diting_android/state/launcher_icon_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ThemePage extends ConsumerWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pureBlack = ref.watch(pureBlackProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    warmDemoSchemes(
      brightness: dark ? Brightness.dark : Brightness.light,
      pureBlack: pureBlack,
    );
    final transition = ref.watch(tabTransitionProvider);
    final glass = ref.watch(liquidGlassModeProvider);
    final barStyle = ref.watch(bottomBarStyleProvider);
    return CommonScaffold(
      title: context.l10n.appearanceTitle,
      body: PageBody(
        children: [
          // Large preview: the legacy app has none, but all nine sub pages build
          // their thumbnails on the same MiniScreen.
          const _ThemePreview(),
          generateSection(
            title: context.l10n.appearanceInterfaceSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.sun,
                title: context.l10n.dayNightTitle,
                subtitle: ref.watch(themeModeProvider).label(context.l10n),
                onPressed: () => context.push(SystemPaths.dayNight),
              ),
              NavEntryRow(
                glyph: AppGlyphs.palette,
                title: context.l10n.appearancePaletteTitle,
                subtitle: ref.watch(paletteProvider).label(context.l10n),
                onPressed: () => context.push(SystemPaths.colorStyle),
              ),
              NavEntryRow(
                glyph: AppGlyphs.blur,
                title: context.l10n.homeOpacityTitle,
                subtitle: context.l10n.appearanceHomeOpacitySubtitle,
                onPressed: () => context.push(SystemPaths.homeOpacity),
              ),
              NavEntryRow(
                glyph: AppGlyphs.dashboard,
                title: context.l10n.bottomBarCustomTitle,
                subtitle: context.l10n.appearanceBottomBarSelected(
                  ref.watch(bottomBarProvider).length,
                ),
                onPressed: () => context.push(SystemPaths.bottomBar),
              ),
              // Retained entries, after the legacy ones.
              ListItem.toggle(
                title: Text(context.l10n.appearancePureBlack),
                subtitle: Text(
                  dark
                      ? context.l10n.appearancePureBlackOn
                      : context.l10n.appearancePureBlackOff,
                ),
                leading: const GlyphIcon(AppGlyphs.pureBlack),
                value: pureBlack,
                onChanged: dark
                    ? (value) =>
                          ref.read(pureBlackProvider.notifier).toggle(value)
                    : null,
              ),
              NavEntryRow(
                glyph: AppGlyphs.font,
                title: context.l10n.appearanceFontSection,
                subtitle: fontLabelOf(
                  ref.watch(importedFontsProvider),
                  ref.watch(selectedFontFamilyProvider),
                ),
                onPressed: () => context.push(SystemPaths.fontFamily),
              ),
              NavEntryRow(
                glyph: AppGlyphs.iconTile,
                title: context.l10n.launcherIconTitle,
                subtitle: ref.watch(launcherIconProvider).label(context.l10n),
                onPressed: () => context.push(SystemPaths.launcherIcon),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.appearanceHomeSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.textShort,
                title: context.l10n.homeSentenceTitle,
                subtitle: context.l10n.appearanceHomeSentenceSubtitle,
                onPressed: () => context.push(SystemPaths.homeSentence),
              ),
              NavEntryRow(
                glyph: AppGlyphs.status,
                title: context.l10n.appearanceNotification,
                subtitle: context.l10n.appearanceNotificationSubtitle,
                onPressed: () => context.push(SystemPaths.notification),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.appearanceBackgroundSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.photos,
                title: context.l10n.backgroundTitle,
                subtitle: ref.watch(customBackgroundProvider).enabled
                    ? context.l10n.commonEnabled
                    : context.l10n.commonDisabled,
                onPressed: () => context.push(SystemPaths.background),
              ),
              ListItem.toggle(
                title: Text(context.l10n.appearanceHaptic),
                subtitle: Text(context.l10n.appearanceHapticSubtitle),
                leading: const GlyphIcon(AppGlyphs.motion),
                value: ref.watch(hapticProvider),
                onChanged: (value) =>
                    ref.read(hapticProvider.notifier).toggle(value),
              ),
              // Retained entries, after the legacy ones.
              ListItem<BottomBarStyle>.options(
                title: Text(context.l10n.appearanceBottomBarStyle),
                subtitle: Text(
                  barStyle.isFloating
                      ? context.l10n.appearanceBottomBarStyleFloating
                      : context.l10n.appearanceBottomBarStyleDocked,
                ),
                leading: const GlyphIcon(AppGlyphs.sliders),
                options: BottomBarStyle.values,
                value: barStyle,
                textBuilder: (value) => value.label(context.l10n),
                onChanged: (value) =>
                    ref.read(bottomBarStyleProvider.notifier).select(value),
              ),
              ListItem<TabTransition>.options(
                title: Text(context.l10n.appearanceTabTransition),
                subtitle: Text(context.l10n.appearanceTabTransitionSubtitle),
                leading: const GlyphIcon(AppGlyphs.motion),
                options: TabTransition.values,
                value: transition,
                textBuilder: (value) => value.label(context.l10n),
                onChanged: (value) =>
                    ref.read(tabTransitionProvider.notifier).select(value),
              ),
              ListItem<LiquidGlassMode>.options(
                title: Text(context.l10n.appearanceLiquidGlass),
                subtitle: Text(glass.label(context.l10n)),
                leading: const GlyphIcon(AppGlyphs.liquidGlass),
                options: LiquidGlassMode.values,
                value: glass,
                textBuilder: (value) => value.label(context.l10n),
                onChanged: (value) =>
                    ref.read(liquidGlassModeProvider.notifier).select(value),
              ),
            ],
            footer: context.l10n.appearanceMotionFooter,
          ),
        ],
      ),
    );
  }
}

class _ThemePreview extends ConsumerStatefulWidget {
  const _ThemePreview();

  @override
  ConsumerState<_ThemePreview> createState() => _ThemePreviewState();
}

class _ThemePreviewState extends ConsumerState<_ThemePreview>
    with SingleTickerProviderStateMixin {
  static const _phoneWidth = 180.0;

  late final AnimationController _controller;
  int _selected = 0;
  int? _previous;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1,
    );
  }

  void _select(int index) {
    if (index == _selected) {
      return;
    }
    setState(() {
      _previous = _selected;
      _selected = index;
    });
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) {
        setState(() => _previous = null);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final pureBlack = ref.watch(pureBlackProvider);
    final floating = ref.watch(bottomBarStyleProvider).isFloating;
    final glass = ref.watch(liquidGlassModeProvider).enabled;
    final transition = ref.watch(tabTransitionProvider);
    final brightness = switch (mode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final scheme = demoColorScheme(
      seed: ref.watch(paletteProvider).effectiveSeed,
      brightness: brightness,
      pureBlack: pureBlack,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: _phoneWidth,
            child: AspectRatio(
              aspectRatio: 9 / 17,
              child: ClipRSuperellipse(
                borderRadius: AppRadius.all(AppCorner.fit(_phoneWidth)),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (_, _) => MiniScreen(
                    colorScheme: scheme,
                    floatingBar: floating,
                    liquidGlass: glass,
                    selected: _selected,
                    previous: _previous,
                    progress: _previous == null ? 1 : _controller.value,
                    transition: transition,
                    onSelect: _select,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
