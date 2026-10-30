// ignore_for_file: sort_child_properties_last
import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/data/vpn/block_response_settings.dart';
import 'package:diting/router.dart';
import 'package:diting/state/auto_update_providers.dart';
import 'package:diting/state/ca_inspection_providers.dart';
import 'package:diting/state/subscription_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/page_intro.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Rule control (upstream `RuleControlScreen`): master switch, URL rules, block response
/// and subscription updates; block, allow and override lists stay in their own hub cards.
class RuleControlPage extends ConsumerWidget {
  const RuleControlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final domainRules = settings.domainRulesEnabled;
    final blockMode = BlockResponseMode.fromStorage(
      settings.blockResponseModeRaw,
    );
    // CA readiness comes from the real channel: `caReadyProvider` reads
    // `CaCertificateService.inspect()`, so an installed certificate is not reported as missing.
    final caReady = ref.watch(caReadyProvider);
    final inspectionApps = settings.httpInspectionPackages;
    final subscriptions = ref.watch(subscriptionEntriesProvider).value;
    final mirrors = ref.watch(mirrorTemplatesProvider).value;
    final autoUpdate = ref.watch(autoUpdateSettingsProvider);
    final footnote = AppTextStyle.footnote
        .of(context)
        .copyWith(color: context.colorScheme.onSurfaceVariant);
    final urlSubtitle = !caReady
        ? context.l10n.ruleControlUrlNotReadyCa
        : !settings.httpInspectionEnabled
        ? context.l10n.ruleControlUrlNotReadyInspection
        : inspectionApps.isEmpty
        ? context.l10n.ruleControlUrlNotReadyApps
        : !domainRules
        ? context.l10n.ruleControlUrlPaused
        : context.l10n.ruleControlUrlRunning;
    return CommonScaffold(
      title: context.l10n.hubRuleControl,
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.ruleControlIntro),
          generateSection(
            title: context.l10n.ruleControlFilterSection,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.rules),
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
              ListItem(
                leading: const GlyphIcon(AppGlyphs.target),
                title: Text(context.l10n.ruleControlUrlRules),
                subtitle: Text(urlSubtitle),
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
            title: context.l10n.ruleControlPolicySection,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.block),
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
            title: context.l10n.ruleControlSubsSection,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.cloudSync),
                title: Text(context.l10n.ruleControlSubsTitle),
                subtitle: Text(context.l10n.ruleControlSubsSubtitle),
                trailing: Text(
                  subscriptions == null
                      ? '—'
                      : context.l10n.ruleControlCount(subscriptions.length),
                  style: footnote,
                ),
                onTap: () => context.push(Routes.subscriptions),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.refresh),
                title: Text(context.l10n.autoUpdateTitle),
                subtitle: Text(
                  !autoUpdate.enabled
                      ? context.l10n.ruleControlAutoUpdateOff
                      : switch (autoUpdate.schedule) {
                          AutoUpdateSchedule.interval =>
                            context.l10n.ruleControlAutoUpdateOn(
                              autoUpdate.intervalHours,
                            ),
                          AutoUpdateSchedule.daily =>
                            context.l10n.ruleControlAutoUpdateDaily(
                              _clock(autoUpdate.timeMinutes),
                            ),
                          AutoUpdateSchedule.everyOtherDay =>
                            context.l10n.ruleControlAutoUpdateEveryOtherDay(
                              _clock(autoUpdate.timeMinutes),
                            ),
                        },
                ),
                onTap: () => context.push('/hub/rules/auto-update'),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.layers),
                title: Text(context.l10n.mirrorTplTitle),
                subtitle: Text(context.l10n.ruleControlMirrorSubtitle),
                trailing: Text(
                  mirrors == null
                      ? '—'
                      : context.l10n.ruleControlCount(mirrors.length),
                  style: footnote,
                ),
                onTap: () => context.push('/hub/rules/mirrors'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _clock(int minutes) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }
}

/// Block response settings (upstream `BlockResponseSettingsScreen`), persisted in
/// `dns_vpn_prefs` (`block_response_mode` plus four `dynamic_block_*` keys) and published
/// by `buildDnsConfig` on next start.
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
              for (final option in BlockResponseMode.values)
                ListItem(
                  leading: GlyphIcon(
                    option == mode ? AppGlyphs.checkCircle : AppGlyphs.block,
                    size: 20,
                  ),
                  title: Text(option.label(context.l10n)),
                  subtitle: Text(option.description(context.l10n)),
                  trailing: option == mode ? const SelectionCheck() : null,
                  onTap: () {
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
                leading: const GlyphIcon(AppGlyphs.motion),
                title: Text(context.l10n.blockResponseEnableDynamic),
                subtitle: Text(context.l10n.blockResponseEnableDynamicSubtitle),
                value: policy.enabled,
                onChanged: (value) {
                  policy.copyWith(enabled: value).write(settings);
                  ref.read(legacySettingsRevisionProvider.notifier).bump();
                },
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.sliders),
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
    // Upstream clamps: 2-100 requests, 10-300 s window, 60-3600 s hold.
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
              style: AppTextStyle.footnote
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
