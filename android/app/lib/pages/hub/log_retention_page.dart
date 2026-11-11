/// Log mode (legacy `ui/LogRetentionSettingsScreen.kt`): `dns_log_mode`, `log_retention_days`.
/// Crash logs live on the 故障排查 page in 数据与维护.
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
              for (final option in LegacyLogMode.values)
                ListItem(
                  leading: GlyphIcon(
                    mode == option ? AppGlyphs.checkCircle : AppGlyphs.logs,
                    size: 20,
                  ),
                  title: Text(option.label(context.l10n)),
                  subtitle: Text(option.description(context.l10n)),
                  trailing: mode == option ? const SelectionCheck() : null,
                  onTap: () =>
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
                for (final days in _retentionOptions)
                  ListItem(
                    leading: GlyphIcon(
                      retentionDays == days
                          ? AppGlyphs.checkCircle
                          : AppGlyphs.clock,
                      size: 20,
                    ),
                    title: Text(context.l10n.logRetentionKeepDays('$days')),
                    trailing: retentionDays == days
                        ? const SelectionCheck()
                        : null,
                    onTap: () =>
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

/// Floating log window settings. The permission row is re-read on resume, since the grant happens
/// on a system screen the app cannot observe.
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

  /// Turning it on without the permission sends the user to grant it right away; the switch stays
  /// on, so returning with the grant needs no second tap.
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
              leading: const GlyphIcon(AppGlyphs.eye),
              title: Text(l10n.logRetentionOverlayLogs),
              subtitle: Text(l10n.logRetentionOverlayBody),
              value: enabled,
              onChanged: _toggle,
            ),
            if (enabled && granted != null)
              ListItem(
                leading: GlyphIcon(
                  granted ? AppGlyphs.checkCircle : AppGlyphs.warning,
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
                    : const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                onTap: granted ? null : _requestPermission,
              ),
          ],
          footer: l10n.logRetentionOverlayNote,
        ),
        if (enabled) ...[
          ListHeader(title: l10n.floatingLogSizeTitle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedControl<int>(
              segments: [
                (0, l10n.floatingLogSizeSmall),
                (1, l10n.floatingLogSizeMedium),
                (2, l10n.floatingLogSizeLarge),
              ],
              value: ref.watch(floatingLogPanelSizeProvider),
              onChanged: ref.read(floatingLogPanelSizeProvider.notifier).set,
            ),
          ),
          const SizedBox(height: 12),
          generateSection(
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
