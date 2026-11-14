/// A10: the local HTTP API settings page. It shows the token, lets the user copy/regenerate it and
/// starts or stops the loopback server.
library;

import 'package:diting_android/state/local_api_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class LocalApiPage extends ConsumerWidget {
  const LocalApiPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(localApiProvider);
    final notifier = ref.read(localApiProvider.notifier);
    return CommonScaffold(
      title: l10n.localApiTitle,
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.localApiIntro),
          if (state.error != null)
            PageIntroCard(text: l10n.localApiError(state.error!)),
          generateSection(
            title: l10n.localApiToken,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.key),
                title: SelectableText(
                  state.token,
                  style: context.listSubtitleStyle,
                ),
                trailing: IconButton(
                  tooltip: l10n.localApiCopy,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: state.token));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l10n.localApiCopied)));
                  },
                  icon: const GlyphIcon(AppGlyphs.copy),
                ),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.refresh),
                title: Text(l10n.localApiRegenerate),
                onTap: notifier.regenerate,
              ),
            ],
          ),
          generateSection(
            title: l10n.localApiEndpoints,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.link),
                title: Text(l10n.localApiEndpointStatus),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.link),
                title: Text(l10n.localApiEndpointVersion),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.info),
                title: Text(l10n.localApiHeaderHint),
              ),
            ],
          ),
          generateSection(
            title: l10n.localApiPort,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.lock),
                title: Text(l10n.localApiEnable),
                subtitle: Text(
                  state.running
                      ? l10n.localApiRunning(state.port ?? 0)
                      : l10n.localApiStopped,
                ),
                trailing: CommonSwitch(
                  value: state.running,
                  onChanged: notifier.setEnabled,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
