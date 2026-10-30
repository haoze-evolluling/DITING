/// Notifications, background and language sub pages; keys in `notification_settings_prefs`.
library;

import 'dart:async';
import 'dart:io';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/native/notification_bridge.dart';
import 'package:diting/data/native/permissions_bridge.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/pages/appearance/appearance_inputs.dart';
import 'package:diting/pages/appearance/notification_stats_section.dart';
import 'package:diting/state/notification_stats_providers.dart';
import 'package:diting/state/permission_providers.dart';
import 'package:diting/state/settings_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/nav_entry_row.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Notification settings. The keys live in `notification_settings_prefs`: the
/// foreground service reads that container, so writing elsewhere silently does nothing.
class ThemeNotificationPage extends ConsumerStatefulWidget {
  const ThemeNotificationPage({super.key});

  @override
  ConsumerState<ThemeNotificationPage> createState() =>
      _ThemeNotificationPageState();
}

class _ThemeNotificationPageState extends ConsumerState<ThemeNotificationPage> {
  late final TextEditingController _running;
  late final TextEditingController _stopped;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(notificationSettingsProvider);
    _running = TextEditingController(text: settings.runningText);
    _stopped = TextEditingController(text: settings.stoppedText);
    // Labels follow the in-app language; refreshed here so a language switch reaches the shade.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      writeNotificationStatLabels(
        ref.read(legacySettingsProvider),
        context.l10n,
      );
    });
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _running.dispose();
    _stopped.dispose();
    super.dispose();
  }

  /// The services read the text from prefs, so a running notification only picks the edit up when
  /// it is told to rebuild. Debounced: typing must not repaint the shade on every keystroke.
  void _refreshNotification() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(notificationBridgeProvider).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);
    return CommonScaffold(
      title: context.l10n.appearanceNotification,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.notificationPersistentSection,
            footer: context.l10n.notificationPersistentFooter,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.notificationPersistent),
                subtitle: Text(context.l10n.notificationPersistentSubtitle),
                leading: const GlyphIcon(AppGlyphs.status),
                value: settings.persistent,
                onChanged: (value) {
                  notifier.setPersistent(value);
                  _refreshNotification();
                },
              ),
            ],
          ),
          NotificationStatsSection(
            enabled: settings.persistent,
            onChanged: _refreshNotification,
          ),
          // The header also supplies the gap a titled section leaves above it.
          ListHeader(title: context.l10n.notificationTextSection),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FieldGroupCard(
              children: [
                LabeledTextField(
                  label: context.l10n.notificationTextRunning,
                  controller: _running,
                  minLines: 2,
                  hintText: context.l10n.notificationTextHint,
                  onChanged: (value) {
                    notifier.setRunningText(value);
                    _refreshNotification();
                  },
                ),
                LabeledTextField(
                  label: context.l10n.notificationTextStopped,
                  controller: _stopped,
                  minLines: 2,
                  hintText: context.l10n.notificationTextHint,
                  onChanged: (value) {
                    notifier.setStoppedText(value);
                    _refreshNotification();
                  },
                ),
              ],
            ),
          ),
          ListFooter(text: context.l10n.notificationTextFooter),
          generateSection(
            title: context.l10n.notificationPermissions,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.lock,
                title: context.l10n.notificationSystemPermission,
                subtitle: context.l10n.notificationSystemPermissionSubtitle,
                // Opening the page directly beats a hint: the hint only told people what
                // to do and left them to find it in Settings.
                onPressed: () => ref
                    .read(permissionStatesProvider.notifier)
                    .openSystemSettings(AppPermission.notification),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline edit row; `ListItem.input` opens a dialog on tap instead.
void _hint(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 2200),
    ),
  );
}

/// App background. Picking goes through the native `PickVisualMedia` channel; without
/// it the page still works and only "add image" reports that it is unavailable.
class ThemeBackgroundPage extends ConsumerWidget {
  const ThemeBackgroundPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = ref.watch(customBackgroundProvider);
    final notifier = ref.read(customBackgroundProvider.notifier);
    return CommonScaffold(
      title: context.l10n.backgroundTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.backgroundSection,
            footer: context.l10n.backgroundFooter,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.backgroundEnable),
                subtitle: Text(
                  background.uris.isEmpty ? context.l10n.backgroundPickFirst : context.l10n.backgroundBehindPages,
                ),
                leading: const GlyphIcon(AppGlyphs.photos),
                value: background.enabled,
                onChanged: background.uris.isEmpty ? null : notifier.setEnabled,
              ),
              NavEntryRow(
                glyph: AppGlyphs.add,
                title: context.l10n.backgroundAddImage,
                subtitle: context.l10n.backgroundAddImageSubtitle,
                onPressed: () async {
                  final error = await notifier.pickAndAdd();
                  if (error != null && context.mounted) _hint(context, error);
                },
              ),
            ],
          ),
          if (background.uris.isNotEmpty)
            generateSection(
              title: context.l10n.backgroundAdded,
              footer: context.l10n.backgroundAddedFooter,
              items: [
                _WallpaperGrid(
                  uris: background.uris,
                  currentUri: background.currentUri,
                  onSelect: notifier.select,
                  onRemove: notifier.remove,
                ),
              ],
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: NullStatus(
                illustration: NullStatusIllustration.data,
                label: context.l10n.backgroundEmpty,
                description: context.l10n.backgroundEmptyDescription,
              ),
            ),
        ],
      ),
    );
  }
}

class _WallpaperGrid extends StatelessWidget {
  const _WallpaperGrid({
    required this.uris,
    required this.currentUri,
    required this.onSelect,
    required this.onRemove,
  });

  final List<String> uris;
  final String? currentUri;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    // Thumbnails use a phone-like 9:16 ratio in three columns.
    const aspectRatio = 9 / 16;
    final rows = <Widget>[];
    for (var i = 0; i < uris.length; i += 3) {
      final rowUris = uris.sublist(i, (i + 3).clamp(0, uris.length));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            for (final uri in rowUris)
              Expanded(
                child: _WallpaperThumbnail(
                  uri: uri,
                  aspectRatio: aspectRatio,
                  selected: uri == currentUri,
                  onTap: () => onSelect(uri),
                  onLongPress: () => _confirmRemove(context, uri),
                ),
              ),
            for (var pad = rowUris.length; pad < 3; pad++)
              const Expanded(child: SizedBox.shrink()),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(spacing: 8, children: rows),
    );
  }

  Future<void> _confirmRemove(BuildContext context, String uri) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.backgroundDeleteTitle,
        // The last action is destructive: `destructive` tints it red on a filled
        // background, consistent with the other confirmation dialogs.
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
        child: Text(context.l10n.backgroundDeleteConfirm),
      ),
    );
    if (confirmed == true) onRemove(uri);
  }
}

/// One wallpaper thumbnail, checked when selected.
class _WallpaperThumbnail extends StatefulWidget {
  const _WallpaperThumbnail({
    required this.uri,
    required this.aspectRatio,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final String uri;
  final double aspectRatio;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_WallpaperThumbnail> createState() => _WallpaperThumbnailState();
}

class _WallpaperThumbnailState extends State<_WallpaperThumbnail> {
  late Future<String?> _path;

  @override
  void initState() {
    super.initState();
    _path = _resolve();
  }

  Future<String?> _resolve() async {
    final container = ProviderScope.containerOf(context, listen: false);
    return container.read(backgroundBridgeProvider).resolve(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: ClipRSuperellipse(
          borderRadius: AppRadius.md,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: colorScheme.surfaceContainerHighest),
              FutureBuilder<String?>(
                future: _path,
                builder: (context, snapshot) {
                  final path = snapshot.data;
                  if (path == null) return const SizedBox.shrink();
                  return Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  );
                },
              ),
              if (widget.selected) ...[
                ColoredBox(color: Colors.black.withValues(alpha: 0.2)),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: ShapeDecoration(
                      shape: AppShape.circle,
                      color: colorScheme.primary,
                    ),
                    child: GlyphIcon(
                      AppGlyphs.check,
                      size: 14,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsBackgroundPage extends ConsumerWidget {
  const SettingsBackgroundPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(foregroundBackgroundProvider);
    final notifier = ref.read(foregroundBackgroundProvider.notifier);
    return CommonScaffold(
      title: context.l10n.foregroundTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.foregroundPrivacySection,
            footer: context.l10n.foregroundPrivacyFooter,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.foregroundHide),
                subtitle: Text(context.l10n.foregroundHideSubtitle),
                leading: const GlyphIcon(AppGlyphs.eyeOff),
                value: state.hideFromRecents,
                onChanged: notifier.setHideFromRecents,
              ),
            ],
          ),
          generateSection(
            title: context.l10n.foregroundRouting,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.foregroundBypassLan),
                subtitle: Text(context.l10n.foregroundBypassLanSubtitle),
                leading: const GlyphIcon(AppGlyphs.devices),
                value: state.bypassLan,
                onChanged: notifier.setBypassLan,
              ),
              ListItem<LegacyIpv6Mode>.options(
                title: const Text('IPv6'),
                subtitle: Text(state.ipv6Mode.description(context.l10n)),
                leading: const GlyphIcon(AppGlyphs.link),
                options: LegacyIpv6Mode.values,
                value: state.ipv6Mode,
                textBuilder: (mode) => mode.label(context.l10n),
                onChanged: notifier.setIpv6Mode,
              ),
            ],
          ),
          generateSection(
            title: context.l10n.foregroundStability,
            footer: context.l10n.foregroundBatteryFooter,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.settingsAutoStartTitle),
                subtitle: Text(context.l10n.settingsAutoStartSubtitle),
                leading: const GlyphIcon(AppGlyphs.sync),
                value: ref.watch(autoStartOnLaunchProvider),
                onChanged: ref.read(autoStartOnLaunchProvider.notifier).toggle,
              ),
              ListItem.toggle(
                title: Text(context.l10n.settingsVpnWatchdogTitle),
                subtitle: Text(context.l10n.settingsVpnWatchdogSubtitle),
                leading: const GlyphIcon(AppGlyphs.vpn),
                value: ref.watch(vpnWatchdogProvider),
                onChanged: ref.read(vpnWatchdogProvider.notifier).toggle,
              ),
              NavEntryRow(
                glyph: AppGlyphs.bolt,
                title: context.l10n.foregroundIgnoreBattery,
                subtitle: context.l10n.foregroundIgnoreBatterySubtitle,
                // Asks the system instead of describing the screen path; the request shows the
                // "always run in background" dialog when the ROM allows it.
                onPressed: () => ref
                    .read(permissionStatesProvider.notifier)
                    .request(AppPermission.batteryOptimization),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The interface language list. Every entry of [AppLanguageMode] is offered; adding a language
/// only needs a new `lib/l10n/app_<code>.arb` and one enum entry.
class SettingsLanguagePage extends ConsumerWidget {
  const SettingsLanguagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(languageModeProvider);
    return CommonScaffold(
      title: context.l10n.languageTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.languageInterfaceSection,
            footer: context.l10n.languageInterfaceFooter,
            items: [
              for (final option in AppLanguageMode.values)
                ListItem(
                  title: Text(option.label(context.l10n)),
                  leading: GlyphIcon(
                    option == mode ? AppGlyphs.check : AppGlyphs.language,
                    color: option == mode ? context.colorScheme.primary : null,
                  ),
                  trailing: option == mode
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () =>
                      ref.read(languageModeProvider.notifier).select(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
