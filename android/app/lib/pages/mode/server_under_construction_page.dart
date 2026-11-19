import 'package:diting_android/router.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Retained server-mode entry: the mode is being rebuilt from scratch, so the page only says so
/// and offers a way back to mode selection.
class ServerUnderConstructionPage extends StatelessWidget {
  const ServerUnderConstructionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonScaffold(
      title: context.l10n.workModeServerTitle,
      body: PageBody(
        children: [
          const SizedBox(height: 48),
          Center(
            child: IconBadge(
              glyph: AppGlyphs.dns,
              size: 64,
              glyphSize: 32,
              color: colorScheme.surfaceContainerHigh,
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.serverUnderConstructionTitle,
            textAlign: TextAlign.center,
            style: AppTextStyle.title1.of(context, emphasized: true),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              context.l10n.serverUnderConstructionBody,
              textAlign: TextAlign.center,
              style: context.listCaptionStyle,
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TonalButton(
              size: TonalButtonSize.bar,
              glyph: AppGlyphs.chevronBack,
              label: context.l10n.modeSelectTitle,
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(Routes.modeSelect);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
