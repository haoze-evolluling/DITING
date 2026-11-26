// ignore_for_file: sort_child_properties_last
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/block_response_settings.dart';
import 'package:diting_android/state/ca_inspection_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class RuleControlPage extends ConsumerWidget {
  const RuleControlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final withTunnel = ref.watch(workModeProvider).hasTunnelFeatures;
    final domainRules = settings.domainRulesEnabled;
    final blockMode = BlockResponseMode.fromStorage(
      settings.blockResponseModeRaw,
    );
    final caReady = ref.watch(caReadyProvider);
    final inspectionApps = settings.httpInspectionPackages;
    final footnote = AppTextRole.supportingText
        .of(context)
        .copyWith(color: context.colorScheme.onSurfaceVariant);
    String urlSubtitle() {
      if (!caReady) {
        return context.l10n.ruleControlUrlNotReadyCa;
      }
      if (!settings.httpInspectionEnabled) {
        return context.l10n.ruleControlUrlNotReadyInspection;
      }
      if (inspectionApps.isEmpty) {
        return context.l10n.ruleControlUrlNotReadyApps;
      }
      if (!domainRules) {
        return context.l10n.ruleControlUrlPaused;
      }
      return context.l10n.ruleControlUrlRunning;
    }

    return CommonScaffold(
      title: context.l10n.hubRuleControl,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.ruleControlFilterSection,
            items: [
              ListItem.toggle(
                leading: const Icon(TablerIcons.list_details),
                title: Text(context.l10n.ruleControlDomainRules),
                subtitle: Text(
                  domainRules
                      ? context.l10n.ruleControlDomainRulesOn
                      : context.l10n.ruleControlDomainRulesOff,
                ),
                value: domainRules,
                onChanged: (value) {
                  settings.setDomainRulesEnabled(value);
                  ref.read(legacySettingsRevisionProvider.notifier).bump();
                },
              ),
              if (withTunnel)
                ListItem(
                  leading: const Icon(TablerIcons.target),
                  title: Text(context.l10n.ruleControlUrlRules),
                  subtitle: Text(urlSubtitle()),
                  trailing: Text(
                    settings.httpInspectionEnabled &&
                            settings.addressRulesEnabled &&
                            caReady
                        ? context.l10n.stateRunning
                        : context.l10n.ruleControlNotReady,
                    style: footnote,
                  ),
                  onTap: () => context.push('/hub/https-inspection'),
                ),
            ],
          ),
          generateSection(
            title: context.l10n.ruleControlDiagnosticsSection,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.search),
                title: Text(context.l10n.ruleTestTitle),
                subtitle: Text(context.l10n.ruleTestEnterSubtitle),
                onTap: () => context.push('/hub/rules/test'),
              ),
              ListItem(
                leading: const Icon(TablerIcons.trophy),
                title: Text(context.l10n.hitRankingTitle),
                subtitle: Text(context.l10n.hitRankingEntrySubtitle),
                onTap: () => context.push('/logs/hit-ranking'),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.ruleControlControlSection,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.player_pause),
                title: Text(context.l10n.blockPauseTitle),
                subtitle: Text(context.l10n.blockPauseEntrySubtitle),
                onTap: () => context.push('/hub/rules/pause'),
              ),
              ListItem(
                leading: const Icon(TablerIcons.ban),
                title: Text(context.l10n.ruleControlBlockResponse),
                subtitle: Text(
                  settings.dynamicBlockEnabled
                      ? context.l10n.ruleControlDynamicSummary(
                          blockMode.label(context.l10n),
                        )
                      : blockMode.label(context.l10n),
                ),
                onTap: () => context.push('/hub/rules/block-response'),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.ruleControlDomainSection,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.shield),
                title: Text(context.l10n.hubBlocklist),
                subtitle: Text(context.l10n.hubBlocklistDescription),
                onTap: () => context.push('/rules/block'),
              ),
              ListItem(
                leading: const Icon(TablerIcons.rosette_discount_check),
                title: Text(context.l10n.hubAllowlist),
                subtitle: Text(context.l10n.hubAllowlistDescription),
                onTap: () => context.push('/rules/allow'),
              ),
              ListItem(
                leading: const Icon(TablerIcons.arrows_exchange),
                title: Text(context.l10n.hubRewrite),
                subtitle: Text(context.l10n.hubRewriteDescription),
                onTap: () => context.push('/rules/rewrite'),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.hubModuleMore,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.automation),
                title: Text(context.l10n.automationTitle),
                subtitle: Text(context.l10n.automationSubtitle),
                onTap: () => context.push('/automation'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class BlockResponsePage extends ConsumerWidget {
  const BlockResponsePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final mode = BlockResponseMode.fromStorage(settings.blockResponseModeRaw);
    final policy = DynamicBlockPolicy.read(settings);
    return CommonScaffold(
      title: context.l10n.ruleControlBlockResponse,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.blockResponseFixedSection,
            items: [
              ListItem<BlockResponseMode>.options(
                leading: const Icon(TablerIcons.ban),
                title: Text(context.l10n.blockResponseFixedSection),
                subtitle: Text(mode.description(context.l10n)),
                value: mode,
                options: BlockResponseMode.values,
                textBuilder: (option) => option.label(context.l10n),
                onChanged: (option) {
                  settings.setBlockResponseModeRaw(option.storageValue);
                  ref.read(legacySettingsRevisionProvider.notifier).bump();
                },
              ),
            ],
            footer: context.l10n.blockResponseFixedFooter,
          ),
          generateSection(
            title: context.l10n.blockResponseDynamicSection,
            items: [
              ListItem.toggle(
                leading: const Icon(TablerIcons.shield_bolt),
                title: Text(context.l10n.blockResponseEnableDynamic),
                subtitle: Text(context.l10n.blockResponseEnableDynamicSubtitle),
                value: policy.enabled,
                onChanged: (value) {
                  policy.copyWith(enabled: value).write(settings);
                  ref.read(legacySettingsRevisionProvider.notifier).bump();
                },
              ),
              ListItem(
                leading: const Icon(TablerIcons.adjustments),
                title: Text(context.l10n.blockResponseParameters),
                subtitle: Text(
                  context.l10n.blockResponseParamsSummary(
                    policy.requestThreshold,
                    policy.windowSeconds,
                    policy.nxDomainDurationSeconds,
                  ),
                ),
                onTap: policy.enabled
                    ? () => _editParameters(context, ref, policy)
                    : null,
              ),
            ],
            footer: context.l10n.blockResponseDynamicFooter,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _editParameters(
    BuildContext context,
    WidgetRef ref,
    DynamicBlockPolicy policy,
  ) async {
    final result = await showFloatingDialog<DynamicBlockPolicy>(
      context: context,
      child: _DynamicParameterDialog(policy: policy),
    );
    if (result == null) {
      return;
    }
    result.write(ref.read(legacySettingsProvider));
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

class _DynamicParameterDialog extends StatefulWidget {
  const _DynamicParameterDialog({required this.policy});

  final DynamicBlockPolicy policy;

  @override
  State<_DynamicParameterDialog> createState() =>
      _DynamicParameterDialogState();
}

class _DynamicParameterDialogState extends State<_DynamicParameterDialog> {
  late final _threshold = TextEditingController(
    text: '${widget.policy.requestThreshold}',
  );
  late final _window = TextEditingController(
    text: '${widget.policy.windowSeconds}',
  );
  late final _duration = TextEditingController(
    text: '${widget.policy.nxDomainDurationSeconds}',
  );
  String? _error;

  @override
  void dispose() {
    _threshold.dispose();
    _window.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _save() {
    final threshold = int.tryParse(_threshold.text);
    final window = int.tryParse(_window.text);
    final duration = int.tryParse(_duration.text);
    String? error;
    if (threshold == null || threshold < 2 || threshold > 100) {
      error = context.l10n.blockResponseThresholdError;
    } else if (window == null || window < 10 || window > 300) {
      error = context.l10n.blockResponseWindowError;
    } else if (duration == null || duration < 60 || duration > 3600) {
      error = context.l10n.blockResponseDurationError;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(
      DynamicBlockPolicy(
        enabled: true,
        requestThreshold: threshold!,
        windowSeconds: window!,
        nxDomainDurationSeconds: duration!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.blockResponseParameters,
      hasFields: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          TextField(
            controller: _threshold,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.blockResponseThresholdLabel,
              helperText: context.l10n.blockResponseThresholdHelper,
            ),
          ),
          TextField(
            controller: _window,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.blockResponseWindowLabel,
              helperText: context.l10n.blockResponseWindowHelper,
            ),
          ),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.blockResponseDurationLabel,
              helperText: context.l10n.blockResponseDurationHelper,
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: AppTextRole.supportingText
                  .of(context)
                  .copyWith(color: context.colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(onPressed: _save, child: Text(context.l10n.commonSave)),
      ],
    );
  }
}
