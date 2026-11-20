import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_upstream_shared.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerUpstreamPage extends ConsumerWidget {
  const ServerUpstreamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverUpstreamTitle,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final upstream = config.upstream;
    return CommonScaffold(
      title: context.l10n.serverUpstreamTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverUpstreamScheduling,
            items: [
              ListItem<String>.options(
                leading: GlyphIcon(serverModeGlyph(upstream.mode), size: 20),
                title: Text(context.l10n.serverUpstreamMode),
                subtitle: Text(serverModeDescription(context, upstream.mode)),
                value: upstream.mode,
                options: serverUpstreamModes,
                textBuilder: (mode) => serverModeLabel(context, mode),
                onChanged: (mode) => _save(
                  context,
                  ref,
                  config.copyWith(upstream: upstream.copyWith(mode: mode)),
                ),
              ),
            ],
            footer: context.l10n.serverUpstreamModeNote,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
  ) async {
    try {
      await ref.read(serverControllerProvider.notifier).saveConfig(config);
      if (context.mounted) {
        showAppSnack(context, context.l10n.serverUpstreamSaved);
      }
    } catch (error) {
      if (context.mounted) showAppSnack(context, error.toString());
    }
  }
}
