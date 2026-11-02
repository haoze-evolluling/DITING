// ignore_for_file: sort_child_properties_last
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/agent/agent_analysis_target.dart';
import 'package:diting_android/pages/hub/agent_analysis_sheet.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/routes/standalone_routes.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// AI analysis settings (upstream `AgentApiSettingsScreen`). Reports are rendered by
/// [AgentAnalysisSheet], which the log pages open directly; this page configures the provider and
/// offers the two test entries.
class AgentApiPage extends ConsumerWidget {
  const AgentApiPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentApiProvider);
    final notifier = ref.read(agentApiProvider.notifier);
    final provider = state.activeProvider;
    final colorScheme = context.colorScheme;
    final ready = state.ready;
    return CommonScaffold(
      title: context.l10n.hubAiAnalysis,
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  Row(
                    children: [
                      GlyphIcon(
                        AppGlyphs.sparkle,
                        size: 24,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.enabled ? context.l10n.agentApiEnabled : context.l10n.agentApiDisabled,
                          style: context.listTitleStyle,
                        ),
                      ),
                      CommonSwitch(
                        value: state.enabled,
                        onChanged: notifier.setEnabled,
                      ),
                    ],
                  ),
                  Text(
                    provider == null
                        ? context.l10n.agentApiNoProvider
                        : context.l10n.agentApiCurrentProvider(
                            provider.name,
                            provider.model.isEmpty
                                ? context.l10n.agentApiNoModel
                                : provider.model,
                          ),
                    style: context.listSubtitleStyle,
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      MetaChip(
                        label: provider?.hasKey == true
                            ? context.l10n.agentApiKeyConfigured
                            : context.l10n.agentApiChipKeyMissing,
                      ),
                      MetaChip(
                        label: context.l10n.agentApiTemperature(
                          state.temperature.toStringAsFixed(1),
                        ),
                      ),
                      MetaChip(label: context.l10n.agentApiProviderChip),
                    ],
                  ),
                  if (!ready)
                    Text(
                      state.enabled
                          ? context.l10n.agentApiReadyHintOn
                          : context.l10n.agentApiReadyHintOff,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
          generateSection(
            title: context.l10n.agentApiSectionProvider,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.devices),
                title: Text(context.l10n.agentProvidersTitle),
                subtitle: Text(
                  context.l10n.agentApiProvidersSubtitle(state.providers.length),
                ),
                onTap: () => context.push(HubPaths.agentProviders),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.sliders),
                title: Text(context.l10n.agentParamsTitle),
                subtitle: Text(context.l10n.agentParamsSubtitle),
                onTap: () => context.push(HubPaths.agentParams),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.agentApiSectionTest,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.dns),
                title: Text(context.l10n.agentApiTestDomain),
                subtitle: Text(context.l10n.agentApiTestDomainSubtitle),
                onTap: () => openAgentAnalysis(
                  context,
                  const AgentDomainTarget('example-tracker.com'),
                ),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.dataUsage),
                title: Text(context.l10n.agentApiTestTraffic),
                subtitle: Text(context.l10n.agentApiTestTrafficSubtitle),
                onTap: () =>
                    openAgentAnalysis(context, const AgentTrafficTarget()),
              ),
            ],
            footer: ready
                ? context.l10n.agentApiTestFooterReady
                : context.l10n.agentApiTestFooterNotReady,
          ),
          generateSection(
            title: context.l10n.agentApiSectionEntries,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.layers),
                title: Text(context.l10n.agentApiCacheTable),
                subtitle: Text(context.l10n.agentApiCacheTableSubtitle),
                onTap: () => context.push('/logs/cache'),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.requests),
                title: Text(context.l10n.agentApiRequests),
                subtitle: Text(context.l10n.agentApiRequestsSubtitle),
                onTap: () => context.push('/requests'),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.dashboard),
                title: Text(context.l10n.agentApiDashboard),
                subtitle: Text(context.l10n.agentApiDashboardSubtitle),
                // `/logs` is a tab root: pushing it stacks a second copy of the shell branch and
                // trips go_router's duplicate page-key assert, so open the full-screen twin and
                // fall back to a branch switch.
                onTap: () {
                  if (!pushStandalone(context, Routes.logs)) {
                    openLocation(context, Routes.logs);
                  }
                },
              ),
            ],
            footer: context.l10n.agentApiEntriesFooter,
          ),
          generateSection(
            title: context.l10n.agentApiSectionReset,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.reset),
                title: Text(context.l10n.agentApiResetItem),
                subtitle: Text(context.l10n.agentApiResetSubtitle),
                onTap: () => _reset(context, notifier),
              ),
            ],
          ),
          PageIntroText(text: context.l10n.agentApiFooter),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _reset(BuildContext context, AgentApiNotifier notifier) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.agentApiResetTitle,
        destructive: true,
        child: Text(context.l10n.agentApiResetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.agentApiResetConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true) notifier.reset();
  }
}
