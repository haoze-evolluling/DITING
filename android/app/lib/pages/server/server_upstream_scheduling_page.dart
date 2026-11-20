import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_upstream_shared.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerUpstreamSchedulingPage extends ConsumerWidget {
  const ServerUpstreamSchedulingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverUpstreamScheduling,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final upstream = config.upstream;
    return CommonScaffold(
      title: context.l10n.serverUpstreamScheduling,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverUpstreamMode,
            items: [
              ServerOptionRow<String>(
                glyph: serverModeGlyph(upstream.mode),
                title: context.l10n.serverUpstreamScheduling,
                value: upstream.mode,
                options: [
                  for (final mode in serverUpstreamModes)
                    ServerOption(
                      value: mode,
                      label: serverModeLabel(context, mode),
                      subtitle: serverModeDescription(context, mode),
                      glyph: serverModeGlyph(mode),
                    ),
                ],
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
