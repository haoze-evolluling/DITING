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
    final l10n = context.l10n;
    final barStyle = ref.watch(bottomBarStyleProvider);
    return CommonScaffold(
      title: l10n.appearanceTitle,
      body: PageBody(
        children: [
          const _ThemePreview(),
          generateSection(
            title: l10n.appearanceThemeSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.sun,
                title: l10n.dayNightTitle,
                subtitle: ref.watch(themeModeProvider).label(l10n),
                onPressed: () => context.push(SystemPaths.dayNight),
              ),
              NavEntryRow(
                glyph: AppGlyphs.palette,
                title: l10n.appearancePaletteTitle,
                subtitle: ref.watch(paletteProvider).label(l10n),
                onPressed: () => context.push(SystemPaths.colorStyle),
              ),
              NavEntryRow(
                glyph: AppGlyphs.iconTile,
                title: l10n.launcherIconTitle,
                subtitle: ref.watch(launcherIconProvider).label(l10n),
                onPressed: () => context.push(SystemPaths.launcherIcon),
              ),
            ],
          ),
          generateSection(
            title: l10n.appearanceLayoutSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.font,
                title: l10n.appearanceFontSection,
                subtitle: fontLabelOf(
                  ref.watch(importedFontsProvider),
                  ref.watch(selectedFontFamilyProvider),
                ),
                onPressed: () => context.push(SystemPaths.fontFamily),
              ),
              NavEntryRow(
                glyph: AppGlyphs.blur,
                title: l10n.homeOpacityTitle,
                subtitle: l10n.appearanceHomeOpacitySubtitle,
                onPressed: () => context.push(SystemPaths.homeOpacity),
              ),
              NavEntryRow(
                glyph: AppGlyphs.dashboard,
                title: l10n.bottomBarCustomTitle,
                subtitle: l10n.appearanceBottomBarSelected(
                  ref.watch(bottomBarProvider).length,
                ),
                onPressed: () => context.push(SystemPaths.bottomBar),
              ),
              ListItem<BottomBarStyle>.options(
                title: Text(l10n.appearanceBottomBarStyle),
                subtitle: Text(
                  barStyle.isFloating
                      ? l10n.appearanceBottomBarStyleFloating
                      : l10n.appearanceBottomBarStyleDocked,
                ),
                leading: const GlyphIcon(AppGlyphs.sliders),
                options: BottomBarStyle.values,
                value: barStyle,
                textBuilder: (value) => value.label(l10n),
                onChanged: (value) =>
                    ref.read(bottomBarStyleProvider.notifier).select(value),
              ),
            ],
          ),
          generateSection(
            title: l10n.appearanceBackgroundSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.photos,
                title: l10n.backgroundTitle,
                subtitle: ref.watch(customBackgroundProvider).enabled
                    ? l10n.commonEnabled
                    : l10n.commonDisabled,
                onPressed: () => context.push(SystemPaths.background),
              ),
              NavEntryRow(
                glyph: AppGlyphs.motion,
                title: l10n.appearanceFeedbackMotionTitle,
                subtitle: l10n.appearanceFeedbackMotionSubtitle,
                onPressed: () => context.push(SystemPaths.feedbackMotion),
              ),
            ],
          ),
          generateSection(
            title: l10n.appearanceHomeNotificationSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.textShort,
                title: l10n.homeSentenceTitle,
                subtitle: l10n.appearanceHomeSentenceSubtitle,
                onPressed: () => context.push(SystemPaths.homeSentence),
              ),
              NavEntryRow(
                glyph: AppGlyphs.notification,
                title: l10n.appearanceNotification,
                subtitle: l10n.appearanceNotificationSubtitle,
                onPressed: () => context.push(SystemPaths.notification),
              ),
            ],
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
    warmDemoSchemes(brightness: brightness, pureBlack: pureBlack);
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
                borderRadius: AppRadius.standard,
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
