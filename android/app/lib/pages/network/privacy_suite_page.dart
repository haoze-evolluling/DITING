library;

import 'package:diting_android/state/privacy_providers.dart';
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
          generateSection(
            title: l10n.privacyDnsSection,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.eye_off),
                title: Text(l10n.privacyBlockHttpsSvcb),
                subtitle: Text(l10n.privacyBlockHttpsSvcbDesc),
                trailing: CommonSwitch(
                  value: state.blockHttpsSvcb,
                  onChanged: notifier.setBlockHttpsSvcb,
                  semanticLabel: l10n.privacyBlockHttpsSvcb,
                ),
              ),
              ListItem(
                leading: const Icon(TablerIcons.lock),
                title: Text(l10n.privacyRebinding),
                subtitle: Text(l10n.privacyRebindingDesc),
                trailing: CommonSwitch(
                  value: state.rebindingProtection,
                  onChanged: notifier.setRebindingProtection,
                  semanticLabel: l10n.privacyRebinding,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
