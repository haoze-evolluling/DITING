/// On-demand page (upstream `views/config/on_demand.dart`).
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_android/pages/config/config_common.dart';
import 'package:diting_android/pages/config/on_demand_capabilities.dart';
import 'package:diting_android/pages/server/server_platform_probe.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_android/state/on_demand_runner.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'on_demand_ssid_form.dart';

class OnDemandConfigPage extends ConsumerWidget {
  const OnDemandConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = ref.watch(configResourcesProvider);
    final notifier = ref.read(configResourcesProvider.notifier);
    final rules = resources.ssidRules;
    final decision = ref.watch(onDemandDecisionProvider);
    return CommonScaffold(
      title: context.l10n.odTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: context.l10n.odApplyNow,
          onPressed: () => _applyNow(context, ref),
        ),
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.ssidAdd,
          onPressed: () => showSsidForm(context, ref),
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.wifi),
                title: Text(context.l10n.odEnable),
                subtitle: Text(
                  resources.onDemand
                      ? _decisionSummary(decision, context.l10n)
                      : context.l10n.odDisableBody,
                ),
                value: resources.onDemand,
                onChanged: (value) => _setEnabled(context, ref, value),
              ),
            ],
            footer:
                context.l10n.odNote,
          ),
          if (resources.onDemand) _DecisionCard(decision: decision),
          if (resources.onDemand)
            generateSection(
              title: context.l10n.odAllowlist,
              actions: [
                IconButtonData(
                  glyph: AppGlyphs.add,
                  tooltip: context.l10n.ssidAdd,
                  onPressed: () => showSsidForm(context, ref),
                ),
              ],
              items: [
                if (rules.isEmpty)
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.wifiOff),
                    title: Text(context.l10n.odNoSsid),
                    subtitle: Text(context.l10n.odNoSsidBody),
                    onTap: () => showSsidForm(context, ref),
                  )
                else
                  for (final rule in rules)
                    ListItem(
                      leading: GlyphIcon(
                        rule.enabled ? AppGlyphs.wifi : AppGlyphs.wifiOff,
                        size: 20,
                      ),
                      title: Text(rule.ssid),
                      subtitle: Text(_ruleSummary(rule, context.l10n)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 2,
                        children: [
                          ConfigRemoveButton(
                            tooltip: context.l10n.odEditSsidTooltip(rule.ssid),
                            glyph: AppGlyphs.edit,
                            onPressed: () =>
                                showSsidForm(context, ref, existing: rule.ssid),
                          ),
                          ConfigRemoveButton(
                            tooltip: context.l10n.odDeleteSsidTooltip(rule.ssid),
                            onPressed: () => notifier.removeSsid(rule.ssid),
                          ),
                        ],
                      ),
                      onTap: () =>
                          showSsidForm(context, ref, existing: rule.ssid),
                    ),
              ],
              footer:
                  context.l10n.odDelayNote,
            ),
          const _NetworkSection(),
          const _BatterySection(),
        ],
      ),
    );
  }
}

String _ruleSummary(MockSsidRule rule, AppL10n l10n) {
  final parts = <String>[
    if (rule.cellular) l10n.odCellular,
    if (rule.wifi) 'Wi-Fi',
  ];
  final kinds = parts.isEmpty ? l10n.odKindsNone : parts.join(' / ');
  final delay = rule.delayMs == 0
      ? l10n.ssidImmediate
      : l10n.odDelayValue('${rule.delayMs}');
  return '$kinds · $delay';
}

/// One line for the switch's subtitle, so the current outcome is visible without opening a page.
String _decisionSummary(SsidDecision decision, AppL10n l10n) =>
    switch (decision.state) {
      SsidMatchState.disabled => l10n.odStateDisabled,
      SsidMatchState.unknown => l10n.odStateUnknown,
      SsidMatchState.noWifi => l10n.odStateNoWifi,
      SsidMatchState.matched => l10n.odStateMatched(
        decision.rule?.ssid ?? '',
      ),
      SsidMatchState.unmatched => l10n.odStateUnmatched,
    };

/// Turns the switch on and immediately applies it: flipping the toggle alone only wrote a
/// preference, so the tunnel state never followed the whitelist until the next restart.
Future<void> _setEnabled(
  BuildContext context,
  WidgetRef ref,
  bool value,
) async {
  ref.read(configResourcesProvider.notifier).setOnDemand(value);
  if (!value) {
    showConfigHint(context, context.l10n.odDisabledHint);
    return;
  }
  final outcome = await ref.read(onDemandRunnerProvider).apply(force: true);
  if (!context.mounted) return;
  showConfigHint(context, outcome.label(context.l10n));
}

/// Re-evaluates the whitelist against the current network; the page has no network callback, so
/// this is how a user applies it after switching Wi-Fi.
Future<void> _applyNow(BuildContext context, WidgetRef ref) async {
  final outcome = await ref.read(onDemandRunnerProvider).apply(force: true);
  if (!context.mounted) return;
  showConfigHint(context, outcome.label(context.l10n));
}

/// What the whitelist decides for the network the device is on now. The card exists because a
/// list alone never tells the user whether the tunnel would start.
class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.decision});

  final SsidDecision decision;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (glyph, title, tone) = switch (decision.state) {
      SsidMatchState.disabled => (
        AppGlyphs.wifiOff,
        context.l10n.odPillDisabled,
        colorScheme.onSurfaceVariant,
      ),
      SsidMatchState.unknown => (AppGlyphs.locate, context.l10n.odPillUnknown, colorScheme.warning),
      SsidMatchState.noWifi => (
        AppGlyphs.wifiOff,
        context.l10n.odPillNoWifi,
        colorScheme.onSurfaceVariant,
      ),
      SsidMatchState.matched => (
        AppGlyphs.check,
        context.l10n.odPillWillStart,
        colorScheme.primary,
      ),
      SsidMatchState.unmatched => (
        AppGlyphs.wifi,
        context.l10n.odPillWillNotStart,
        colorScheme.warning,
      ),
    };
    final rule = decision.rule;
    return generateSection(
      title: context.l10n.odDecision,
      items: [
        ListItem(
          leading: GlyphIcon(glyph, size: 20, color: tone),
          title: Text(
            title,
            style: context.listTitleStyle.copyWith(color: tone),
          ),
          subtitle: Text(
            rule == null
                ? _decisionSummary(decision, context.l10n)
                : _ruleSummary(rule, context.l10n),
          ),
        ),
      ],
      footer:
          context.l10n.odDecisionFooter,
    );
  }
}

/// The name of the joined network, read from the platform channel; the row is also the place to
/// re-read it, since the network can change while the page is open.
class _NetworkSection extends ConsumerWidget {
  const _NetworkSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final async = ref.watch(currentSsidProvider);
    final ssid = async.asData?.value;
    final unknown = async.hasValue && ssid == null;
    return generateSection(
      title: context.l10n.odCurrentNetwork,
      items: [
        ListItem(
          leading: const GlyphIcon(AppGlyphs.wifi, size: 20),
          title: Text(context.l10n.odWifiName),
          subtitle: Text(describeSsid(ssid, context.l10n)),
          trailing: ConfigRemoveButton(
            tooltip: context.l10n.odReadAgain,
            glyph: AppGlyphs.refresh,
            onPressed: () => ref.invalidate(currentSsidProvider),
          ),
          onTap: () => ref.invalidate(currentSsidProvider),
        ),
        if (unknown)
          ListItem(
            leading: const GlyphIcon(AppGlyphs.locate, size: 20),
            title: Text(context.l10n.odPermission),
            subtitle: Text(context.l10n.odPermissionBody),
            trailing: Text(
              context.l10n.odNotGranted,
              style: context.listCaptionStyle.copyWith(
                color: colorScheme.warning,
              ),
            ),
          ),
      ],
      footer: unknown
          ? context.l10n.odWifiUnreadable
          : context.l10n.odSsidPrivacy,
    );
  }
}

/// Battery-optimization allowlist, the one prerequisite the app can actually query and request.
class _BatterySection extends ConsumerWidget {
  const _BatterySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final async = ref.watch(batteryOptimizationProvider);
    final state = async.asData?.value;
    final (label, color) = switch (state) {
      BatteryOptimizationState.ignored => (context.l10n.odBatteryJoined, colorScheme.primary),
      BatteryOptimizationState.notIgnored => (context.l10n.odBatteryNotJoined, colorScheme.warning),
      BatteryOptimizationState.unavailable ||
      null => (context.l10n.odBatteryUnavailable, context.colorScheme.onSurfaceVariant),
    };
    return generateSection(
      title: context.l10n.odPrerequisites,
      items: [
        ListItem(
          leading: const GlyphIcon(AppGlyphs.bolt, size: 20),
          title: Text(context.l10n.odIgnoreBattery),
          subtitle: Text(
            state == BatteryOptimizationState.ignored
                ? context.l10n.odBatteryOk
                : state == BatteryOptimizationState.notIgnored
                ? context.l10n.odBatteryAsk
                : context.l10n.odBatteryNoChannel,
          ),
          trailing: Text(
            label,
            style: context.listCaptionStyle.copyWith(color: color),
          ),
          onTap: state == BatteryOptimizationState.notIgnored
              ? () => _request(context, ref)
              : null,
        ),
      ],
      footer: context.l10n.odBatteryFooter,
    );
  }

  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final state = await requestBatteryOptimizationAccess(ref);
    if (!context.mounted) return;
    showConfigHint(context, switch (state) {
      BatteryOptimizationState.ignored => context.l10n.odBatteryJoinedHint,
      BatteryOptimizationState.notIgnored => context.l10n.odBatteryStillOff,
      BatteryOptimizationState.unavailable => context.l10n.odBatteryUnsupportedHint,
    });
  }
}
