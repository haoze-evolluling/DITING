library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ThemeFeedbackMotionPage extends ConsumerWidget {
  const ThemeFeedbackMotionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pureBlack = ref.watch(pureBlackProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final transition = ref.watch(tabTransitionProvider);
    final glass = ref.watch(liquidGlassModeProvider);
    return CommonScaffold(
      title: context.l10n.appearanceFeedbackMotionTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.appearanceFeedbackSection,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.appearancePureBlack),
                subtitle: Text(
                  dark
                      ? context.l10n.appearancePureBlackOn
                      : context.l10n.appearancePureBlackOff,
                ),
                leading: const Icon(TablerIcons.device_desktop),
                value: pureBlack,
                onChanged: dark
                    ? (value) =>
                          ref.read(pureBlackProvider.notifier).toggle(value)
                    : null,
              ),
              ListItem.toggle(
                title: Text(context.l10n.appearanceHaptic),
                subtitle: Text(context.l10n.appearanceHapticSubtitle),
                leading: const Icon(TablerIcons.device_mobile_vibration),
                value: ref.watch(hapticProvider),
                onChanged: (value) =>
                    ref.read(hapticProvider.notifier).toggle(value),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.appearanceMotionSection,
            footer: context.l10n.appearanceMotionFooter,
            items: [
              ListItem<TabTransition>.options(
                title: Text(context.l10n.appearanceTabTransition),
                subtitle: Text(context.l10n.appearanceTabTransitionSubtitle),
                leading: const Icon(TablerIcons.wind),
                options: TabTransition.values,
                value: transition,
                textBuilder: (value) => value.label(context.l10n),
                onChanged: (value) =>
                    ref.read(tabTransitionProvider.notifier).select(value),
              ),
              ListItem<LiquidGlassMode>.options(
                title: Text(context.l10n.appearanceLiquidGlass),
                subtitle: Text(glass.label(context.l10n)),
                leading: const Icon(TablerIcons.droplet),
                options: LiquidGlassMode.values,
                value: glass,
                textBuilder: (value) => value.label(context.l10n),
                onChanged: (value) =>
                    ref.read(liquidGlassModeProvider.notifier).select(value),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
