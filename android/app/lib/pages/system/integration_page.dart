/// Guide for the platform integrations that have no settings of their own: the home screen widget,
/// the `diting://` subscription deep link and the automation actions. Read-only; the actions are
/// performed from the launcher, another app or adb.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class IntegrationPage extends ConsumerWidget {
  const IntegrationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CommonScaffold(
      title: context.l10n.integrationTitle,
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          _IntegrationCard(
            glyph: AppGlyphs.appsList,
            title: context.l10n.integrationWidgetTitle,
            body: context.l10n.integrationWidgetBody,
          ),
          const SizedBox(height: 12),
          _IntegrationCard(
            glyph: AppGlyphs.link,
            title: context.l10n.integrationDeepLinkTitle,
            body: context.l10n.integrationDeepLinkBody,
          ),
          const SizedBox(height: 12),
          _IntegrationCard(
            glyph: AppGlyphs.bolt,
            title: context.l10n.integrationAutomationTitle,
            body: _automationBody(context),
          ),
        ],
      ),
    );
  }

  String _automationBody(BuildContext context) {
    final l10n = context.l10n;
    return '${l10n.integrationAutomationBody}\n\n'
        '${l10n.integrationAutomationStart}: com.haoze.diting.action.START\n'
        '${l10n.integrationAutomationStop}: com.haoze.diting.action.STOP\n'
        '${l10n.integrationAutomationToggle}: com.haoze.diting.action.TOGGLE\n\n'
        'adb shell am start -a com.haoze.diting.action.TOGGLE '
        '-n com.haoze.diting/.QuickActionActivity';
  }
}

class _IntegrationCard extends StatelessWidget {
  const _IntegrationCard({
    required this.glyph,
    required this.title,
    required this.body,
  });

  final Glyph glyph;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 10,
            children: [
              GlyphIcon(glyph, size: 20, color: colorScheme.primary),
              Expanded(child: Text(title, style: context.listTitleStyle)),
            ],
          ),
          SelectableText(body, style: context.listCaptionStyle),
        ],
      ),
    );
  }
}
