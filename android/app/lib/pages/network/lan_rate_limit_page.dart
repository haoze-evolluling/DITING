/// N9: LAN client rate limiting for the standalone DNS server.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/lan_rate_limit_providers.dart';
import '../../widgets/page_intro.dart';

class LanRateLimitPage extends ConsumerStatefulWidget {
  const LanRateLimitPage({super.key});

  @override
  ConsumerState<LanRateLimitPage> createState() => _LanRateLimitPageState();
}

class _LanRateLimitPageState extends ConsumerState<LanRateLimitPage> {
  late final TextEditingController _exempt;

  @override
  void initState() {
    super.initState();
    _exempt = TextEditingController(
      text: ref.read(lanRateLimitProvider).exemptCsv,
    );
  }

  @override
  void dispose() {
    _exempt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(lanRateLimitProvider);
    final notifier = ref.read(lanRateLimitProvider.notifier);
    return CommonScaffold(
      title: l10n.lanRateLimitTitle,
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.lanRateLimitIntro),
          generateSection(
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.speed),
                title: Text(l10n.lanRateLimitEnable),
                subtitle: Text(l10n.lanRateLimitEnableDesc),
                trailing: Semantics(
                  label: l10n.lanRateLimitEnable,
                  child: Switch(
                    value: state.enabled,
                    onChanged: notifier.setEnabled,
                  ),
                ),
              ),
              _NumberItem(
                label: l10n.lanRateLimitRate,
                value: state.rate,
                step: 5,
                min: 5,
                max: 1000,
                onChanged: notifier.setRate,
              ),
              _NumberItem(
                label: l10n.lanRateLimitBurst,
                value: state.burst,
                step: 10,
                min: 10,
                max: 2000,
                onChanged: notifier.setBurst,
              ),
              _NumberItem(
                label: l10n.lanRateLimitIpv4Prefix,
                value: state.ipv4Prefix,
                step: 1,
                min: 0,
                max: 32,
                onChanged: notifier.setIpv4Prefix,
              ),
              _NumberItem(
                label: l10n.lanRateLimitIpv6Prefix,
                value: state.ipv6Prefix,
                step: 1,
                min: 0,
                max: 128,
                onChanged: notifier.setIpv6Prefix,
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.block),
                title: Text(l10n.lanRateLimitExempt),
                subtitle: TextField(
                  controller: _exempt,
                  decoration: InputDecoration(
                    hintText: l10n.lanRateLimitExemptHint,
                  ),
                  onChanged: notifier.setExemptCsv,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A count row with minus/plus buttons; deliberately not a text field so a small screen cannot
/// overflow the keyboard layout.
class _NumberItem extends StatelessWidget {
  const _NumberItem({
    required this.label,
    required this.value,
    required this.step,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int step;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: '$label −',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.remove),
              onPressed: value <= min ? null : () => onChanged(value - step),
            ),
          ),
          Text('$value'),
          Semantics(
            label: '$label +',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.add),
              onPressed: value >= max ? null : () => onChanged(value + step),
            ),
          ),
        ],
      ),
    );
  }
}
