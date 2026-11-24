import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/ipv6_mode.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'ipv6_mode_labels.dart';

/// IPv6 策略的二级页面：隧道与 DNS 共用同一套三态语义。
class SettingsIpv6Page extends ConsumerWidget {
  const SettingsIpv6Page({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(foregroundBackgroundProvider);
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.ipv6ModeTitle,
      body: PageBody(
        children: [
          generateSection(
            title: l10n.ipv6ModeSectionTitle,
            footer: l10n.ipv6ModeFooter,
            items: [
              ListItem.options(
                leading: const Icon(TablerIcons.link),
                title: Text(l10n.ipv6ModeTitle),
                subtitle: Text(l10n.ipv6ModeSubtitle),
                options: Ipv6Mode.values,
                value: state.ipv6Mode,
                textBuilder: (mode) => ipv6ModeLabel(l10n, mode),
                onChanged: ref
                    .read(foregroundBackgroundProvider.notifier)
                    .setIpv6Mode,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
