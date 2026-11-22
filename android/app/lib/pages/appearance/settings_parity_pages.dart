library;

import 'dart:async';
import 'dart:io';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/notification_bridge.dart';
import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_android/data/native/permissions_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/pages/appearance/appearance_inputs.dart';
import 'package:diting_android/pages/appearance/notification_stats_section.dart';
import 'package:diting_android/state/notification_stats_providers.dart';
import 'package:diting_android/state/permission_providers.dart';
import 'package:diting_android/state/root_dns_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
                leading: const Icon(TablerIcons.bell),
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
                glyph: TablerIcons.lock,
                title: context.l10n.notificationSystemPermission,
                subtitle: context.l10n.notificationSystemPermissionSubtitle,
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
                  background.uris.isEmpty
                      ? context.l10n.backgroundPickFirst
                      : context.l10n.backgroundBehindPages,
                ),
                leading: const Icon(TablerIcons.photo),
                value: background.enabled,
                onChanged: background.uris.isEmpty ? null : notifier.setEnabled,
              ),
              NavEntryRow(
                glyph: TablerIcons.plus,
                title: context.l10n.backgroundAddImage,
                subtitle: context.l10n.backgroundAddImageSubtitle,
                onPressed: () async {
                  final error = await notifier.pickAndAdd();
                  if (error != null && context.mounted) {
                    showAppSnack(
                      context,
                      error,
                      duration: const Duration(milliseconds: 2200),
                    );
                  }
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
          borderRadius: AppRadius.standard,
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
                      shape: AppShape.standard,
                      color: colorScheme.primary,
                    ),
                    child: Icon(
                      TablerIcons.check,
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
    final tunnelMode = ref.watch(workModeProvider).hasTunnelFeatures;
    final rootTakeover = ref.watch(rootDnsTakeoverProvider);
    return CommonScaffold(
      title: context.l10n.foregroundTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.foregroundStartupSection,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.settingsBootAutoStartTitle),
                subtitle: Text(context.l10n.settingsBootAutoStartSubtitle),
                leading: const Icon(TablerIcons.power),
                value: ref.watch(autoStartOnBootProvider),
                onChanged: ref.read(autoStartOnBootProvider.notifier).toggle,
              ),
              ListItem.toggle(
                title: Text(context.l10n.settingsAutoStartTitle),
                subtitle: Text(context.l10n.settingsAutoStartSubtitle),
                leading: const Icon(TablerIcons.rotate_clockwise),
                value: ref.watch(autoStartOnLaunchProvider),
                onChanged: ref.read(autoStartOnLaunchProvider.notifier).toggle,
              ),
              ListItem.toggle(
                title: Text(context.l10n.settingsVpnWatchdogTitle),
                subtitle: Text(context.l10n.settingsVpnWatchdogSubtitle),
                leading: const Icon(TablerIcons.shield_lock),
                value: ref.watch(vpnWatchdogProvider),
                onChanged: ref.read(vpnWatchdogProvider.notifier).toggle,
              ),
            ],
          ),
          generateSection(
            title: context.l10n.foregroundRouting,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.foregroundBypassLan),
                subtitle: Text(context.l10n.foregroundBypassLanSubtitle),
                leading: const Icon(TablerIcons.devices),
                value: state.bypassLan,
                onChanged: notifier.setBypassLan,
              ),
              if (tunnelMode) ...[
                ListItem.toggle(
                  title: Text(context.l10n.tunnelIpv6Title),
                  subtitle: Text(context.l10n.tunnelIpv6Subtitle),
                  leading: const Icon(TablerIcons.link),
                  value: state.tunnelIpv6,
                  onChanged: notifier.setTunnelIpv6,
                ),
                ListItem.toggle(
                  title: Text(context.l10n.dnsAaaaTitle),
                  subtitle: Text(context.l10n.dnsAaaaSubtitle),
                  leading: const Icon(TablerIcons.world),
                  value: state.dnsAaaa,
                  onChanged: notifier.setDnsAaaa,
                ),
                NavEntryRow(
                  glyph: TablerIcons.route,
                  title: context.l10n.routeIncludeTitle,
                  subtitle: state.routeAddress.isEmpty
                      ? context.l10n.routeIncludeAll
                      : context.l10n.routeCidrCount(state.routeAddress.length),
                  onPressed: () => context.push(SystemPaths.routeInclude),
                ),
                NavEntryRow(
                  glyph: TablerIcons.route_off,
                  title: context.l10n.routeExcludeTitle,
                  subtitle: state.routeExcludeAddress.isEmpty
                      ? context.l10n.routeIncludeAll
                      : context.l10n.routeCidrCount(
                          state.routeExcludeAddress.length,
                        ),
                  onPressed: () => context.push(SystemPaths.routeExclude),
                ),
              ],
            ],
          ),
          generateSection(
            title: context.l10n.foregroundBackgroundPermissions,
            footer: context.l10n.foregroundBatteryFooter,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.foregroundHide),
                subtitle: Text(context.l10n.foregroundHideSubtitle),
                leading: const Icon(TablerIcons.eye_off),
                value: state.hideFromRecents,
                onChanged: notifier.setHideFromRecents,
              ),
              NavEntryRow(
                glyph: TablerIcons.battery,
                title: context.l10n.foregroundIgnoreBattery,
                subtitle: context.l10n.foregroundIgnoreBatterySubtitle,
                onPressed: () => ref
                    .read(permissionStatesProvider.notifier)
                    .request(AppPermission.batteryOptimization),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.rootTakeoverSection,
            footer: context.l10n.rootTakeoverFooter,
            items: [
              ListItem.toggle(
                title: Text(context.l10n.rootTakeoverTitle),
                subtitle: Text(
                  tunnelMode
                      ? context.l10n.rootTakeoverSubtitle
                      : context.l10n.rootTakeoverTunnelModesOnly,
                ),
                leading: const Icon(TablerIcons.shield),
                value: rootTakeover,
                onChanged: tunnelMode
                    ? (value) =>
                          ref.read(rootDnsTakeoverProvider.notifier).set(value)
                    : null,
              ),
              if (tunnelMode && rootTakeover)
                _RootTakeoverProbeRow(
                  onRefresh: () => ref.invalidate(rootDnsProbeProvider),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RootTakeoverProbeRow extends ConsumerWidget {
  const _RootTakeoverProbeRow({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final running =
        ref.watch(powerProvider).isRunning &&
        ref.watch(rootDnsTakeoverProvider);
    final probe = ref.watch(rootDnsProbeProvider);
    final subtitle = running
        ? l10n.rootTakeoverRunning
        : probe.when(
            data: (value) => value.available
                ? l10n.rootTakeoverProbeAvailable
                : value.message.isEmpty
                ? l10n.rootTakeoverProbeUnavailableNoReason
                : l10n.rootTakeoverProbeUnavailable(value.message),
            loading: () => l10n.rootTakeoverProbeChecking,
            error: (_, _) => l10n.rootTakeoverProbeUnsupported,
          );
    return NavEntryRow(
      glyph: TablerIcons.refresh,
      title: l10n.rootTakeoverProbeTitle,
      subtitle: subtitle,
      onPressed: onRefresh,
    );
  }
}

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
              ListItem<AppLanguageMode>.options(
                title: Text(context.l10n.languageTitle),
                leading: const Icon(TablerIcons.language),
                value: mode,
                options: AppLanguageMode.values,
                textBuilder: (option) => option.label(context.l10n),
                onChanged: (option) =>
                    ref.read(languageModeProvider.notifier).select(option),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
