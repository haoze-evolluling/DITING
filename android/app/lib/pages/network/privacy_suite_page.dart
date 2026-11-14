/// U10: the privacy suite page — the two DNS switches the engine enforces.
library;

import 'package:diting_android/state/privacy_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacySuitePage extends ConsumerWidget {
  const PrivacySuitePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(privacySettingsProvider);
    final notifier = ref.read(privacySettingsProvider.notifier);
    return CommonScaffold(
      title: l10n.privacySuiteTitle,
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.privacySuiteIntro),
          generateSection(
            title: l10n.privacyDnsSection,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.eyeOff),
                title: Text(l10n.privacyBlockHttpsSvcb),
                subtitle: Text(l10n.privacyBlockHttpsSvcbDesc),
                trailing: Switch(
                  value: state.blockHttpsSvcb,
                  onChanged: notifier.setBlockHttpsSvcb,
                ),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.lock),
                title: Text(l10n.privacyRebinding),
                subtitle: Text(l10n.privacyRebindingDesc),
                trailing: Switch(
                  value: state.rebindingProtection,
                  onChanged: notifier.setRebindingProtection,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
