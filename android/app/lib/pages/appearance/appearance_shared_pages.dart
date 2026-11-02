/// Appearance sub pages: day/night, opacity, dock, sentences. Rest in `settings_parity_pages`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/app/theme/layout.dart';
import 'package:diting_android/pages/appearance/appearance_inputs.dart';
import 'package:diting_shared/widgets/appearance/mini_screen.dart';
import 'package:diting_android/pages/appearance/preview_choice.dart';
import 'package:diting_shared/widgets/appearance/theme_preview.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ThemeDayNightPage extends ConsumerWidget {
  const ThemeDayNightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final pureBlack = ref.watch(pureBlackProvider);
    final seed = ref.watch(paletteProvider).effectiveSeed;
    final floating = ref.watch(bottomBarStyleProvider).isFloating;
    final glass = ref.watch(liquidGlassModeProvider).enabled;
    final schemes = previewSchemes(seed: seed, pureBlack: pureBlack);
    Widget thumb(Brightness brightness) => miniScreenThumb(
      colorScheme: brightness == Brightness.light
          ? schemes.light
          : schemes.dark,
      floatingBar: floating,
      liquidGlass: glass,
    );
    return CommonScaffold(
      title: context.l10n.dayNightTitle,
      body: PageBody(
        children: [
          PreviewChoiceGroup<AppThemeMode>(
            info: Info(label: context.l10n.dayNightInfoLabel),
            value: mode,
            choices: [
              PreviewChoice(
                value: AppThemeMode.system,
                label: context.l10n.commonFollowSystem,
                description: context.l10n.dayNightFollowSystemDescription,
                pictogram: MiniScreenThumb(
                  screen: MiniSplitScreen(
                    light: MiniScreen(
                      colorScheme: schemes.light,
                      floatingBar: floating,
                      liquidGlass: glass,
                    ),
                    dark: MiniScreen(
                      colorScheme: schemes.dark,
                      floatingBar: floating,
                      liquidGlass: glass,
                    ),
                  ),
                ),
              ),
              PreviewChoice(
                value: AppThemeMode.light,
                label: context.l10n.themeModeLight,
                pictogram: thumb(Brightness.light),
              ),
              PreviewChoice(
                value: AppThemeMode.dark,
                label: context.l10n.themeModeDark,
                pictogram: thumb(Brightness.dark),
              ),
            ],
            onChanged: (value) =>
                ref.read(themeModeProvider.notifier).select(value),
            footer: context.l10n.dayNightFooter,
          ),
        ],
      ),
    );
  }
}

/// Home element opacity. Keys come from [HomeLayer.storageKey] (`home_*_opacity`).
class ThemeHomeOpacityPage extends ConsumerWidget {
  const ThemeHomeOpacityPage({super.key});

  static const _interactive = [HomeLayer.powerButton];

  static const _text = [HomeLayer.poem];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opacity = ref.watch(homeOpacityProvider);
    final notifier = ref.read(homeOpacityProvider.notifier);
    return CommonScaffold(
      title: context.l10n.homeOpacityTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.homeOpacityComponents,
            footer: context.l10n.homeOpacityComponentsFooter,
            items: [
              for (final layer in _interactive)
                SliderCardRow(
                  label: layer.label(context.l10n),
                  value: opacity[layer] ?? 1,
                  onChanged: (value) => notifier.set(layer, value),
                ),
            ],
          ),
          generateSection(
            title: context.l10n.homeOpacityText,
            items: [
              for (final layer in _text)
                SliderCardRow(
                  label: layer.label(context.l10n),
                  value: opacity[layer] ?? 1,
                  onChanged: (value) => notifier.set(layer, value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One-line description per dock destination; the enum has no such field.
Map<BottomBarDestination, String> _destinationSubtitles(AppL10n l10n) => {
  BottomBarDestination.home: l10n.bottomBarHomeSubtitle,
  BottomBarDestination.featureHub: l10n.bottomBarFeatureHubSubtitle,
  BottomBarDestination.logDashboard: l10n.bottomBarLogDashboardSubtitle,
  BottomBarDestination.appTraffic: l10n.bottomBarAppTrafficSubtitle,
  BottomBarDestination.networkTools: l10n.bottomBarNetworkToolsSubtitle,
  BottomBarDestination.settings: l10n.bottomBarSettingsSubtitle,
};

/// Dock customization: at least 2 and at most 4 enabled ([maxDockDestinations]), and enabled
/// rows drag into dock order. Rejections must explain themselves.
class ThemeBottomBarPage extends ConsumerWidget {
  const ThemeBottomBarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(bottomBarProvider);
    final notifier = ref.read(bottomBarProvider.notifier);
    final haptic = ref.watch(hapticProvider);
    final hidden = [
      for (final destination in BottomBarDestination.values)
        if (!destinations.contains(destination)) destination,
    ];

    void toggle(BottomBarDestination destination) {
      final selected = destinations.contains(destination);
      if (!notifier.toggle(destination)) {
        showSettingHint(
          context,
          selected
              ? context.l10n.bottomBarMinimumHint
              : context.l10n.appearanceBottomBarMax(maxDockDestinations),
        );
      }
    }

    return CommonScaffold(
      title: context.l10n.bottomBarCustomTitle,
      body: PageBody(
        children: [
          ListHeader(
            title: context.l10n.appearanceBottomBarHeader(
              destinations.length,
              maxDockDestinations,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ReorderableListView.builder(
              // The page already scrolls; a nested scrollable would steal drag gestures.
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: commonProxyDecorator,
              itemCount: destinations.length,
              onReorderItem: notifier.move,
              itemBuilder: (context, index) {
                final destination = destinations[index];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(destination),
                  index: index,
                  child: ItemPositionProvider(
                    position: ItemPosition.get(index, destinations.length),
                    child: _DockDestinationRow(
                      destination: destination,
                      index: index,
                      onToggle: () => toggle(destination),
                    ),
                  ),
                );
              },
            ),
          ),
          ListFooter(
            text: context.l10n.appearanceBottomBarDragBody(maxDockDestinations),
          ),
          generateSection(
            title: context.l10n.bottomBarDisabled,
            items: [
              for (final destination in hidden)
                ListItem.toggle(
                  title: Text(destination.label(context.l10n)),
                  subtitle: Text(
                    _destinationSubtitles(context.l10n)[destination] ?? '',
                  ),
                  leading: GlyphIcon(destination.glyph),
                  value: false,
                  onChanged: (_) => toggle(destination),
                ),
            ],
            footer: context.l10n.bottomBarNewItemFooter,
          ),
          generateSection(
            title: context.l10n.bottomBarFeel,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.appearanceHaptic),
                subtitle: Text(context.l10n.appearanceHapticSubtitle),
                leading: const GlyphIcon(AppGlyphs.motion),
                value: haptic,
                onChanged: (value) =>
                    ref.read(hapticProvider.notifier).toggle(value),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An enabled dock row: tap or switch disables it, the trailing handle drags it.
class _DockDestinationRow extends StatelessWidget {
  const _DockDestinationRow({
    required this.destination,
    required this.index,
    required this.onToggle,
  });

  final BottomBarDestination destination;
  final int index;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      title: Text(destination.label(context.l10n)),
      subtitle: Text(
                    _destinationSubtitles(context.l10n)[destination] ?? '',
                  ),
      leading: GlyphIcon(destination.glyph),
      padding: const EdgeInsets.only(left: 16, right: 4),
      onTap: onToggle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CommonSwitch(value: true, onChanged: (_) => onToggle()),
          ReorderableDragStartListener(
            index: index,
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: SizedBox.square(
                dimension: kMinInteractiveDimension,
                child: Center(child: GlyphIcon(AppGlyphs.dragHandle)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Home sentences: one each for running and stopped; empty hides them.
class ThemeHomeSentencePage extends ConsumerStatefulWidget {
  const ThemeHomeSentencePage({super.key});

  @override
  ConsumerState<ThemeHomeSentencePage> createState() =>
      _ThemeHomeSentencePageState();
}

class _ThemeHomeSentencePageState extends ConsumerState<ThemeHomeSentencePage> {
  late final TextEditingController _running;
  late final TextEditingController _stopped;

  @override
  void initState() {
    super.initState();
    final sentences = ref.read(homeSentenceProvider);
    _running = TextEditingController(text: sentences.running);
    _stopped = TextEditingController(text: sentences.stopped);
  }

  @override
  void dispose() {
    _running.dispose();
    _stopped.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.homeSentenceTitle,
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: FieldGroupCard(
              children: [
                LabeledTextField(
                  label: context.l10n.notificationTextRunning,
                  controller: _running,
                  minLines: 2,
                  onChanged: (value) => ref
                      .read(homeSentenceProvider.notifier)
                      .set(running: value),
                ),
                LabeledTextField(
                  label: context.l10n.notificationTextStopped,
                  controller: _stopped,
                  minLines: 2,
                  onChanged: (value) => ref
                      .read(homeSentenceProvider.notifier)
                      .set(stopped: value),
                ),
              ],
            ),
          ),
          ListFooter(text: context.l10n.homeSentenceFooter),
        ],
      ),
    );
  }
}

/// One-shot SnackBar notice for rule rejections, which otherwise leave no trace
/// beyond the switch bouncing back.
void showSettingHint(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1800),
    ),
  );
}
