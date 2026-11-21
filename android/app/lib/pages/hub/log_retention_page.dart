library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/permissions_bridge.dart';
import 'package:diting_android/pages/appearance/appearance_inputs.dart';
import 'package:diting_android/state/permission_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class LogRetentionPage extends ConsumerWidget {
  const LogRetentionPage({super.key});

  static const _retentionOptions = [1, 7, 30];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(logModeProvider);
    final retentionDays = ref.watch(logRetentionProvider);
    return CommonScaffold(
      title: context.l10n.logRetentionTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.logRetentionDnsLogs,
            items: [
              ListItem<LegacyLogMode>.options(
                leading: const Icon(TablerIcons.logs),
                title: Text(context.l10n.logRetentionDnsLogs),
                subtitle: Text(mode.description(context.l10n)),
                value: mode,
                options: LegacyLogMode.values,
                textBuilder: (option) => option.label(context.l10n),
                onChanged: (option) =>
                    ref.read(logModeProvider.notifier).select(option),
              ),
            ],
            footer: context.l10n.logRetentionOffNote,
          ),
          const _FloatingLogSection(),
          if (mode != LegacyLogMode.off)
            generateSection(
              title: context.l10n.logRetentionCleanup,
              items: [
                ListItem<int>.options(
                  leading: const Icon(TablerIcons.clock),
                  title: Text(context.l10n.logRetentionCleanup),
                  value: retentionDays,
                  options: _retentionOptions,
                  textBuilder: (days) =>
                      context.l10n.logRetentionKeepDays('$days'),
                  onChanged: (days) =>
                      ref.read(logRetentionProvider.notifier).set(days),
                ),
              ],
              footer: context.l10n.logRetentionCleanupNote,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FloatingLogSection extends ConsumerStatefulWidget {
  const _FloatingLogSection();

  @override
  ConsumerState<_FloatingLogSection> createState() =>
      _FloatingLogSectionState();
}

class _FloatingLogSectionState extends ConsumerState<_FloatingLogSection> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(permissionStatesProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _requestPermission() => ref
      .read(permissionStatesProvider.notifier)
      .request(AppPermission.overlay);

  Future<void> _toggle(bool value) async {
    ref.read(floatingLogProvider.notifier).toggle(value);
    if (!value) return;
    final granted = ref
        .read(permissionStatesProvider)
        .value
        ?.of(AppPermission.overlay);
    if (granted == false) await _requestPermission();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final enabled = ref.watch(floatingLogProvider);
    final granted = ref
        .watch(permissionStatesProvider)
        .value
        ?.of(AppPermission.overlay);
    return Column(
      children: [
        generateSection(
          title: l10n.logRetentionOverlay,
          items: [
            ListItem.toggle(
              leading: const Icon(TablerIcons.eye),
              title: Text(l10n.logRetentionOverlayLogs),
              subtitle: Text(l10n.logRetentionOverlayBody),
              value: enabled,
              onChanged: _toggle,
            ),
            if (enabled && granted != null)
              ListItem(
                leading: Icon(
                  granted ? TablerIcons.circle_check : TablerIcons.alert_triangle,
                  size: 20,
                  color: granted ? colorScheme.success : colorScheme.warning,
                ),
                title: Text(l10n.floatingLogPermissionTitle),
                subtitle: Text(
                  granted
                      ? l10n.floatingLogPermissionGranted
                      : l10n.floatingLogPermissionMissing,
                ),
                trailing: granted
                    ? null
                    : const Icon(TablerIcons.chevron_right, size: 18),
                onTap: granted ? null : _requestPermission,
              ),
          ],
          footer: l10n.logRetentionOverlayNote,
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          generateSection(
            title: l10n.floatingLogSizeTitle,
            items: [
              ListItem<int>.options(
                leading: const Icon(TablerIcons.eye),
                title: Text(l10n.floatingLogSizeTitle),
                value: ref.watch(floatingLogPanelSizeProvider),
                options: const [0, 1, 2],
                textBuilder: (size) => switch (size) {
                  0 => l10n.floatingLogSizeSmall,
                  1 => l10n.floatingLogSizeMedium,
                  _ => l10n.floatingLogSizeLarge,
                },
                onChanged: ref.read(floatingLogPanelSizeProvider.notifier).set,
              ),
            ],
          ),
          const SizedBox(height: 12),
          generateSection(
            title: l10n.floatingLogOpacity,
            items: [
              SliderCardRow(
                label: l10n.floatingLogOpacity,
                value: ref.watch(floatingLogOpacityProvider),
                min: 0.3,
                divisions: 14,
                onChanged: ref.read(floatingLogOpacityProvider.notifier).set,
              ),
            ],
            footer: l10n.logRetentionOverlayHowTo,
          ),
        ],
      ],
    );
  }
}
