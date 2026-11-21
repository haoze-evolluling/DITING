import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/router.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ModeSelectPage extends ConsumerStatefulWidget {
  const ModeSelectPage({super.key});

  @override
  ConsumerState<ModeSelectPage> createState() => _ModeSelectPageState();
}

class _ModeSelectPageState extends ConsumerState<ModeSelectPage> {
  AppWorkMode? _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = ref.read(workModeProvider);
  }

  void _select(AppWorkMode mode) {
    if (_expanded == mode && ref.read(workModeProvider) == mode) {
      _confirm(mode);
      return;
    }
    setState(() => _expanded = mode);
    ref.read(workModeProvider.notifier).select(mode);
  }

  void _confirm(AppWorkMode mode) {
    ref.read(workModeProvider.notifier).select(mode);
    ref.read(workModeSelectedProvider.notifier).markSelected();
    if (ref.read(onboardingProvider)) {
      context.pop();
    } else {
      context.pushReplacement(Routes.modeOnboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(workModeProvider);
    final expanded = _expanded ?? current;
    return CommonScaffold(
      title: context.l10n.modeSelectTitle,
      body: PageBody(
        children: [
          PageIntroText(text: context.l10n.modeSharedNote),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                for (final mode in AppWorkMode.values)
                  _WorkModeCard(
                    mode: mode,
                    selected: current == mode,
                    expanded: expanded == mode,
                    onPressed: () => _select(mode),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TonalButton(
              size: TonalButtonSize.bar,
              glyph: TablerIcons.chevron_right,
              label: context.l10n.modeContinue,
              onPressed: () => _confirm(expanded),
            ),
          ),
          ListFooter(text: context.l10n.modeSwitchNote),
        ],
      ),
    );
  }
}

class _WorkModeCard extends StatelessWidget {
  const _WorkModeCard({
    required this.mode,
    required this.selected,
    required this.expanded,
    required this.onPressed,
  });

  final AppWorkMode mode;
  final bool selected;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final accent = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return CommonCard(
      isSelected: selected,
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 12,
            children: [
              IconBadge(
                glyph: _glyphOf(mode),
                size: 44,
                glyphSize: 24,
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.14)
                    : colorScheme.surfaceContainerHigh,
                foregroundColor: accent,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Row(
                      spacing: 6,
                      children: [
                        Flexible(
                          child: Text(
                            mode.title(context.l10n),
                            style: AppTextRole.cardTitle.of(context),
                          ),
                        ),
                        MetaChip(label: mode.badge(context.l10n)),
                      ],
                    ),
                    Text(
                      mode.summary(context.l10n),
                      style: AppTextRole.supportingText
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (selected) const SelectionCheck(),
            ],
          ),
          AnimatedSize(
            duration: commonDuration,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? _ModeFeatureList(mode: mode)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  static IconData _glyphOf(AppWorkMode mode) => switch (mode) {
    AppWorkMode.normal => TablerIcons.stack_2,
    AppWorkMode.express => TablerIcons.bolt,
    AppWorkMode.server => TablerIcons.server_2,
  };
}

class _ModeFeatureList extends StatelessWidget {
  const _ModeFeatureList({required this.mode});

  final AppWorkMode mode;

  static Map<AppWorkMode, List<(IconData, String, String)>> _features(
    AppL10n l10n,
  ) => <AppWorkMode, List<(IconData, String, String)>>{
    AppWorkMode.normal: [
      (TablerIcons.shield_lock, l10n.modeNormalFeature1, l10n.modeNormalFeature1Body),
      (TablerIcons.list_details, l10n.modeNormalFeature2, l10n.modeNormalFeature2Body),
      (
        TablerIcons.rosette_discount_check,
        l10n.modeNormalFeature3,
        l10n.modeNormalFeature3Body,
      ),
      (
        TablerIcons.chart_pie,
        l10n.modeNormalFeature4,
        l10n.modeNormalFeature4Body,
      ),
    ],
    AppWorkMode.express: [
      (TablerIcons.bolt, l10n.modeExpressFeature1, l10n.modeExpressFeature1Body),
      (TablerIcons.arrows_split, l10n.modeExpressFeature2, l10n.modeExpressFeature2Body),
      (
        TablerIcons.cpu_2,
        l10n.modeExpressFeature3,
        l10n.modeExpressFeature3Body,
      ),
      (
        TablerIcons.devices,
        l10n.modeExpressFeature4,
        l10n.modeExpressFeature4Body,
      ),
    ],
    AppWorkMode.server: [
      (TablerIcons.server_2, l10n.modeServerFeature1, l10n.modeServerFeature1Body),
      (TablerIcons.wifi, l10n.modeServerFeature2, l10n.modeServerFeature2Body),
      (TablerIcons.list_details, l10n.modeServerFeature3, l10n.modeServerFeature3Body),
      (TablerIcons.logs, l10n.modeServerFeature4, l10n.modeServerFeature4Body),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final features = _features(context.l10n)[mode] ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.onSurface.withValues(alpha: 0.08),
          ),
          for (final (glyph, title, detail) in features)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(glyph, size: 18, color: colorScheme.primary),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 1,
                    children: [
                      Text(title, style: AppTextRole.bodyStrong.of(context)),
                      Text(
                        detail,
                        style: AppTextRole.caption
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
