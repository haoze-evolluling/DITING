import 'package:diting_android/state/server_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerUpstreamBootstrapPage extends ConsumerWidget {
  const ServerUpstreamBootstrapPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverBootstrapSummary,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final upstream = snapshot.config.upstream;
    return CommonScaffold(
      title: context.l10n.serverBootstrapSummary,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverBootstrapServers,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.dns, size: 20),
                title: Text(
                  upstream.bootstrapEnabled
                      ? context.l10n.commonEnabled
                      : context.l10n.commonDisabled,
                ),
                subtitle: Text(context.l10n.serverBootstrapNote),
              ),
              for (final server in upstream.bootstrap)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.upstream, size: 20),
                  title: Text(server.name.isEmpty ? server.id : server.name),
                  subtitle: Text(server.address),
                ),
              if (upstream.bootstrap.isEmpty)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.info, size: 20),
                  title: Text(context.l10n.serverBootstrapDefault),
                ),
            ],
          ),
          ListFooter(text: context.l10n.serverBootstrapNote),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
