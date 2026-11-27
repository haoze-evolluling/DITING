import 'package:diting_android/data/server/server_launch_models.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerSettingsPage extends ConsumerWidget {
  const ServerSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverSettingsTitle,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final status = snapshot.status;
    final launchAsync = ref.watch(serverLaunchSettingsProvider);
    final launch = launchAsync.value ?? const ServerLaunchSettings();
    final effectivePort = status.running
        ? status.port
        : (config.listen.root ? 53 : 1053);
    return CommonScaffold(
      title: context.l10n.serverSettingsTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverSettingsListen,
            items: [
              ListItem.toggle(
                leading: const Icon(TablerIcons.lock, size: 20),
                title: Text(context.l10n.serverSettingsRoot),
                subtitle: Text(
                  status.active
                      ? context.l10n.serverSettingsRootRunning
                      : context.l10n.serverSettingsRootBody,
                ),
                value: config.listen.root,
                onChanged: status.active
                    ? null
                    : (value) => _saveRoot(context, ref, config, value),
              ),
              ListItem(
                leading: const Icon(TablerIcons.activity, size: 20),
                title: Text(context.l10n.serverPort),
                subtitle: Text(context.l10n.serverPortFixed),
                trailing: Text(
                  '$effectivePort',
                  style: AppTextRole.supportingText
                      .of(context)
                      .copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                        fontFeatures: appTabularFigures,
                      ),
                ),
              ),
              ListItem(
                leading: const Icon(TablerIcons.target, size: 20),
                title: Text(context.l10n.serverSettingsProbeRoot),
                subtitle: Text(context.l10n.serverSettingsProbeRootBody),
                trailing: const Icon(TablerIcons.chevron_right, size: 18),
                onTap: () => _probeRoot(context, ref),
              ),
            ],
            footer: context.l10n.serverSettingsRootNote,
          ),
          generateSection(
            title: context.l10n.serverSettingsLaunch,
            items: [
              ListItem.toggle(
                leading: const Icon(TablerIcons.power, size: 20),
                title: Text(context.l10n.serverSettingsBootAutoStart),
                subtitle: Text(context.l10n.serverSettingsBootAutoStartBody),
                value: launch.autoStart,
                onChanged: launchAsync.hasValue
                    ? (value) => _saveLaunch(
                        context,
                        ref,
                        launch.copyWith(autoStart: value),
                      )
                    : null,
              ),
              ListItem.toggle(
                leading: const Icon(TablerIcons.rotate_clockwise, size: 20),
                title: Text(context.l10n.serverSettingsAutoRestart),
                subtitle: Text(context.l10n.serverSettingsAutoRestartBody),
                value: launch.autoRestart,
                onChanged: launchAsync.hasValue
                    ? (value) => _saveLaunch(
                        context,
                        ref,
                        launch.copyWith(autoRestart: value),
                      )
                    : null,
              ),
            ],
            footer: context.l10n.serverSettingsLaunchNote,
          ),
          generateSection(
            title: context.l10n.serverSettingsRuntime,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.cpu, size: 20),
                title: Text(context.l10n.serverSettingsPid),
                subtitle: Text(context.l10n.serverSettingsPidBody),
                trailing: _RuntimeValue(
                  label: status.running && status.pid > 0
                      ? '${status.pid}'
                      : '—',
                ),
              ),
              ListItem(
                leading: const Icon(TablerIcons.network, size: 20),
                title: Text(context.l10n.serverSettingsAddresses),
                subtitle: Text(
                  status.addresses.isEmpty
                      ? context.l10n.serverSettingsNotRunning
                      : status.addresses.join('  ·  '),
                ),
              ),
              ListItem(
                leading: const Icon(TablerIcons.clock, size: 20),
                title: Text(context.l10n.serverSettingsStartedAt),
                trailing: _RuntimeValue(
                  label: status.startedAt == null
                      ? '—'
                      : _formatTime(status.startedAt!),
                ),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.serverSettingsStorage,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.folder, size: 20),
                title: Text(context.l10n.serverSettingsDataDir),
                subtitle: Text(context.l10n.serverSettingsDataDirBody),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _saveRoot(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
    bool value,
  ) async {
    try {
      await ref
          .read(serverControllerProvider.notifier)
          .saveConfig(
            config.copyWith(
              listen: ServerListenConfig(
                port: value ? 53 : 1053,
                bindAddress: config.listen.bindAddress,
                root: value,
                lan: true,
              ),
            ),
          );
      if (context.mounted) {
        showAppSnack(context, context.l10n.commonSaved);
      }
    } catch (error) {
      if (context.mounted) showAppSnack(context, error.toString());
    }
  }

  Future<void> _saveLaunch(
    BuildContext context,
    WidgetRef ref,
    ServerLaunchSettings next,
  ) async {
    try {
      await ref.read(serverLaunchSettingsProvider.notifier).save(next);
      if (context.mounted) {
        showAppSnack(context, context.l10n.commonSaved);
      }
    } catch (error) {
      if (context.mounted) showAppSnack(context, error.toString());
    }
  }

  Future<void> _probeRoot(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(serverClientProvider).probeRoot();
      if (!context.mounted) return;
      showAppSnack(
        context,
        result.available
            ? context.l10n.serverRootAvailable
            : context.l10n.serverRootUnavailable(
                result.message.isEmpty
                    ? context.l10n.serverRootDenied
                    : result.message,
              ),
      );
    } catch (error) {
      if (context.mounted) showAppSnack(context, error.toString());
    }
  }
}

String _formatTime(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

class _RuntimeValue extends StatelessWidget {
  const _RuntimeValue({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextRole.supportingText
          .of(context)
          .copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontFeatures: appTabularFigures,
          ),
    );
  }
}
