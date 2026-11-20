// ignore_for_file: sort_child_properties_last
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/cleanup/cleanup_models.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DataCleanupPage extends ConsumerWidget {
  const DataCleanupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(cleanupProgressProvider);
    return CommonScaffold(
      title: context.l10n.devDataCleanup,
      body: PageBody(
        children: [
          if (running != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                spacing: 8,
                children: [
                  const CommonCircleLoading(size: 16),
                  Expanded(
                    child: Text(
                      context.l10n.cleanupRunning(running.title(context.l10n)),
                      style: AppTextRole.supportingText.of(context),
                    ),
                  ),
                ],
              ),
            ),
          for (final group in cleanupGroups(context.l10n).entries)
            generateSection(
              title: group.key,
              items: [
                for (final action in group.value)
                  ListItem(
                    leading: GlyphIcon(
                      AppGlyphs.delete,
                      size: 20,
                      color: context.colorScheme.error,
                    ),
                    title: Text(
                      action.title(context.l10n),
                      style: AppTextRole.rowTitle
                          .of(context)
                          .copyWith(color: context.colorScheme.error),
                    ),
                    subtitle: Text(_descriptionOf(context.l10n, action)),
                    onTap: running == null
                        ? () => _confirm(context, ref, action)
                        : null,
                  ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    CleanupAction action,
  ) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: action.title(context.l10n),
        destructive: true,
        child: Text(_confirmTextOf(context.l10n, action)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref.read(cleanupRunnerProvider).run(action);
    if (!context.mounted) return;

    showAppSnack(context, result.message);

    if (action.exitsApp) {
      await _exitApp(context);
    }
  }

  Future<void> _exitApp(BuildContext context) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.cleanupRestartTitle,
        child: Text(context.l10n.cleanupRestartBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.devQuitNow),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SystemNavigator.pop();
    }
  }

  static String _descriptionOf(AppL10n l10n, CleanupAction action) =>
      switch (action) {
        CleanupAction.logs => l10n.cleanupDescLogs,
        CleanupAction.traffic => l10n.cleanupDescTraffic,
        CleanupAction.crash => l10n.cleanupDescCrash,
        CleanupAction.dnsCache => l10n.cleanupDescDnsCache,
        CleanupAction.providerWeights => l10n.cleanupDescProviderWeights,
        CleanupAction.bootstrapWeights => l10n.cleanupDescBootstrapWeights,
        CleanupAction.domainRules => l10n.cleanupDescDomainRules,
        CleanupAction.addressRules => l10n.cleanupDescAddressRules,
        CleanupAction.subscriptions => l10n.cleanupDescSubscriptions,
        CleanupAction.appRules => l10n.cleanupDescAppRules,
        CleanupAction.outboundProxy => l10n.cleanupDescOutboundProxy,
        CleanupAction.caCertificate => l10n.cleanupDescCaCertificate,
        CleanupAction.downloadCache => l10n.cleanupDescDownloadCache,
        CleanupAction.customBackground => l10n.cleanupDescCustomBackground,
        CleanupAction.settingsGuides => l10n.cleanupDescSettingsGuides,
        CleanupAction.allData => l10n.cleanupDescAllData,
      };

  static String _confirmTextOf(AppL10n l10n, CleanupAction action) =>
      switch (action) {
        CleanupAction.logs => l10n.cleanupConfirmLogs,
        CleanupAction.traffic => l10n.cleanupConfirmTraffic,
        CleanupAction.crash => l10n.cleanupConfirmCrash,
        CleanupAction.dnsCache => l10n.cleanupConfirmDnsCache,
        CleanupAction.providerWeights => l10n.cleanupConfirmProviderWeights,
        CleanupAction.bootstrapWeights => l10n.cleanupConfirmBootstrapWeights,
        CleanupAction.domainRules => l10n.cleanupConfirmDomainRules,
        CleanupAction.addressRules => l10n.cleanupConfirmAddressRules,
        CleanupAction.subscriptions => l10n.cleanupConfirmSubscriptions,
        CleanupAction.appRules => l10n.cleanupConfirmAppRules,
        CleanupAction.outboundProxy => l10n.cleanupConfirmOutboundProxy,
        CleanupAction.caCertificate => l10n.cleanupConfirmCaCertificate,
        CleanupAction.downloadCache => l10n.cleanupConfirmDownloadCache,
        CleanupAction.customBackground => l10n.cleanupConfirmCustomBackground,
        CleanupAction.settingsGuides => l10n.cleanupConfirmSettingsGuides,
        CleanupAction.allData => l10n.cleanupConfirmAllData,
      };
}
