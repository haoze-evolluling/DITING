/// N9: LAN client rate limiting for the standalone DNS server.
library;

import 'package:diting_android/state/lan_rate_limit_providers.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_android/widgets/rate_limit_stepper_row.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class LanRateLimitPage extends ConsumerWidget {
  const LanRateLimitPage({super.key});

  Future<void> _editExempt(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l10n = context.l10n;
    final value = await showFloatingDialog<String>(
      context: Navigator.of(context, rootNavigator: true).context,
      child: InputDialog(
        title: l10n.lanRateLimitExempt,
        value: current,
        hintText: l10n.lanRateLimitExemptHint,
        selectAll: true,
      ),
    );
    if (value == null) return;
    ref.read(lanRateLimitProvider.notifier).setExemptCsv(value.trim());
  }

  String _exemptSummary(String csv, AppL10n l10n) {
    final count = csv
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .length;
    return count == 0
        ? l10n.lanRateLimitExemptNone
        : l10n.lanRateLimitExemptCount(count);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(lanRateLimitProvider);
    final notifier = ref.read(lanRateLimitProvider.notifier);
    return CommonScaffold(
      title: l10n.lanRateLimitTitle,
      body: PageBody(
        children: [
          PageIntroCard(
            text: l10n.lanRateLimitIntro,
            extra: [InlineNotice(message: l10n.lanRateLimitRestartNotice)],
          ),
          generateSection(
            title: l10n.lanRateLimitSectionSwitch,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.speed),
                title: Text(l10n.lanRateLimitEnable),
                subtitle: Text(l10n.lanRateLimitEnableDesc),
                trailing: CommonSwitch(
                  value: state.enabled,
                  onChanged: notifier.setEnabled,
                  semanticLabel: l10n.lanRateLimitEnable,
                ),
              ),
            ],
          ),
          generateSection(
            title: l10n.lanRateLimitSectionRate,
            items: [
              RateLimitStepperRow(
                glyph: AppGlyphs.speed,
                label: l10n.lanRateLimitRate,
                value: state.rate,
                step: 5,
                min: 5,
                max: 1000,
                enabled: state.enabled,
                onChanged: notifier.setRate,
              ),
              RateLimitStepperRow(
                glyph: AppGlyphs.connections,
                label: l10n.lanRateLimitBurst,
                value: state.burst,
                step: 10,
                min: 10,
                max: 2000,
                enabled: state.enabled,
                onChanged: notifier.setBurst,
              ),
            ],
          ),
          generateSection(
            title: l10n.lanRateLimitSectionAggregation,
            items: [
              RateLimitStepperRow(
                glyph: AppGlyphs.filter,
                label: l10n.lanRateLimitIpv4Prefix,
                value: state.ipv4Prefix,
                step: 1,
                min: 0,
                max: 32,
                enabled: state.enabled,
                onChanged: notifier.setIpv4Prefix,
              ),
              RateLimitStepperRow(
                glyph: AppGlyphs.filter,
                label: l10n.lanRateLimitIpv6Prefix,
                value: state.ipv6Prefix,
                step: 1,
                min: 0,
                max: 128,
                enabled: state.enabled,
                onChanged: notifier.setIpv6Prefix,
              ),
            ],
          ),
          generateSection(
            title: l10n.lanRateLimitSectionExempt,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.block),
                title: Text(l10n.lanRateLimitExemptManage),
                subtitle: Text(_exemptSummary(state.exemptCsv, l10n)),
                trailing: const GlyphIcon(AppGlyphs.edit),
                onTap: () => _editExempt(context, ref, state.exemptCsv),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
