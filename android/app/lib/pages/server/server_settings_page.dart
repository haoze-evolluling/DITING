import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
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
                leading: const GlyphIcon(AppGlyphs.target, size: 20),
                title: Text(context.l10n.serverSettingsProbeRoot),
                subtitle: Text(context.l10n.serverSettingsProbeRootBody),
                trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
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
