/// Per-app DNS and new-connection rate limiting for normal mode.
library;

import 'dart:async';

import 'package:diting_android/state/connection_rate_limit_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/rate_limit_stepper_row.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ConnectionRateLimitPage extends ConsumerWidget {
  const ConnectionRateLimitPage({super.key});

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    VoidCallback write,
  ) async {
    write();
    final error = await ref
        .read(powerProvider.notifier)
        .applyDnsConfigIfRunning();
    if (error == null || !context.mounted) return;
    showAppSnack(context, context.l10n.connectionRateLimitApplyFailed(error));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(connectionRateLimitProvider);
    final notifier = ref.read(connectionRateLimitProvider.notifier);
    return CommonScaffold(
      title: l10n.connectionRateLimitTitle,
      body: PageBody(
        children: [
          generateSection(
            title: l10n.connectionRateLimitSectionSwitch,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.speed),
                title: Text(l10n.connectionRateLimitEnable),
                subtitle: Text(l10n.connectionRateLimitEnableDesc),
                trailing: CommonSwitch(
                  value: state.enabled,
                  onChanged: (value) => unawaited(
                    _save(context, ref, () => notifier.setEnabled(value)),
                  ),
                  semanticLabel: l10n.connectionRateLimitEnable,
                ),
              ),
            ],
          ),
          generateSection(
            title: l10n.connectionRateLimitSectionParameters,
            footer: l10n.connectionRateLimitFooter,
            items: [
              RateLimitStepperRow(
                glyph: AppGlyphs.speed,
                label: l10n.connectionRateLimitRate,
                value: state.rate,
                min: ConnectionRateLimitSettings.minRate,
                max: ConnectionRateLimitSettings.maxRate,
                step: 5,
                enabled: state.enabled,
                onChanged: (value) => unawaited(
                  _save(context, ref, () => notifier.setRate(value)),
                ),
              ),
              RateLimitStepperRow(
                glyph: AppGlyphs.connections,
                label: l10n.connectionRateLimitBurst,
                value: state.burst,
                min: ConnectionRateLimitSettings.minBurst,
                max: ConnectionRateLimitSettings.maxBurst,
                step: 10,
                enabled: state.enabled,
                onChanged: (value) => unawaited(
                  _save(context, ref, () => notifier.setBurst(value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
