import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    return CommonScaffold(
      title: context.l10n.serverSettingsTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverSettingsRuntime,
            items: [
              ListItem(
                leading: GlyphIcon(
                  status.running ? AppGlyphs.checkCircle : AppGlyphs.pause,
                  size: 20,
                  color: status.running
                      ? context.colorScheme.success
                      : context.colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  status.running
                      ? context.l10n.serverRunning
                      : context.l10n.serverStopped,
                ),
                subtitle: Text(
                  status.addresses.isEmpty
                      ? '0.0.0.0:${status.port}'
                      : status.addresses.join(' · '),
                ),
                trailing: MetaChip(
                  label: status.root
                      ? context.l10n.serverRootMode
                      : context.l10n.serverNonRootMode,
                ),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.sync, size: 20),
                title: Text(context.l10n.workModeSettingTitle),
                subtitle: Text(context.l10n.serverSettingsSwitchModeBody),
                trailing: const GlyphIcon(
                  AppGlyphs.chevronForward,
                  size: 18,
                ),
                onTap: () => context.push(Routes.modeSelect),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.serverSettingsListen,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.lock, size: 20),
                title: Text(context.l10n.serverSettingsRoot),
                subtitle: Text(
                  status.running
                      ? context.l10n.serverSettingsRootRunning
                      : context.l10n.serverSettingsRootBody,
                ),
                value: config.listen.root,
                onChanged: status.running
                    ? null
                    : (value) => _saveRoot(context, ref, config, value),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.status, size: 20),
                title: Text(context.l10n.serverPort),
                subtitle: Text(context.l10n.serverPortFixed),
                trailing: Text(
                  '${status.running ? status.port : (config.listen.root ? 53 : 1053)}',
                  style: AppTextStyle.footnote.of(context).copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                    fontFeatures: appTabularFigures,
                  ),
                ),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.target, size: 20),
                title: Text(context.l10n.serverSettingsProbeRoot),
                subtitle: Text(context.l10n.serverSettingsProbeRootBody),
                trailing: const GlyphIcon(
                  AppGlyphs.chevronForward,
                  size: 18,
                ),
                onTap: () => _probeRoot(context, ref),
              ),
            ],
            footer: context.l10n.serverSettingsRootNote,
          ),
          generateSection(
            title: context.l10n.serverSettingsStorage,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.folder, size: 20),
                title: Text(context.l10n.serverSettingsDataDir),
                subtitle: Text(context.l10n.serverSettingsDataDirBody),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.upstream, size: 20),
                title: Text(context.l10n.serverUpstream),
                subtitle: Text(
                  config.upstream.providers
                      .map((provider) => provider.id)
                      .join(' · '),
                ),
                onTap: () => context.push(ServerRoutes.upstream),
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
      await ref.read(serverControllerProvider.notifier).saveConfig(
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
