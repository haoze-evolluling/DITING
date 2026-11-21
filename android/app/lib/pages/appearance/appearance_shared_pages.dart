library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/app/theme/layout.dart';
import 'package:diting_android/pages/appearance/appearance_inputs.dart';
import 'package:diting_android/widgets/app_snack.dart';
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
    return CommonScaffold(
      title: context.l10n.dayNightTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.dayNightInfoLabel,
            items: [
              ListItem<AppThemeMode>.options(
                leading: const GlyphIcon(AppGlyphs.sun),
                title: Text(context.l10n.dayNightTitle),
                value: mode,
                options: AppThemeMode.values,
                textBuilder: (value) => value.label(context.l10n),
                onChanged: (value) =>
                    ref.read(themeModeProvider.notifier).select(value),
              ),
            ],
            footer: context.l10n.dayNightFooter,
          ),
        ],
      ),
    );
  }
}

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

String _destinationSubtitle(AppL10n l10n, BottomBarDestination destination) =>
    switch (destination) {
      BottomBarDestination.home => l10n.bottomBarHomeSubtitle,
      BottomBarDestination.featureHub => l10n.bottomBarFeatureHubSubtitle,
      BottomBarDestination.logDashboard => l10n.bottomBarLogDashboardSubtitle,
      BottomBarDestination.appTraffic => l10n.bottomBarAppTrafficSubtitle,
      BottomBarDestination.networkTools => l10n.bottomBarNetworkToolsSubtitle,
      BottomBarDestination.settings => l10n.bottomBarSettingsSubtitle,
    };

class ThemeBottomBarPage extends ConsumerWidget {
  const ThemeBottomBarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(bottomBarProvider);
    final notifier = ref.read(bottomBarProvider.notifier);
    final hidden = [
      for (final destination in BottomBarDestination.values)
        if (!destinations.contains(destination)) destination,
    ];

    void toggle(BottomBarDestination destination) {
      final selected = destinations.contains(destination);
      if (!notifier.toggle(destination)) {
        showAppSnack(
          context,
          selected
              ? context.l10n.bottomBarMinimumHint
              : context.l10n.appearanceBottomBarMax(maxDockDestinations),
          duration: const Duration(milliseconds: 1800),
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
                    _destinationSubtitle(context.l10n, destination),
                  ),
                  leading: GlyphIcon(destination.glyph),
                  value: false,
                  onChanged: (_) => toggle(destination),
                ),
            ],
            footer: context.l10n.bottomBarNewItemFooter,
          ),
        ],
      ),
    );
  }
}

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
      subtitle: Text(_destinationSubtitle(context.l10n, destination)),
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
