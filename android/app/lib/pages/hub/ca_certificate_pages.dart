// ignore_for_file: sort_child_properties_last
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/ca_bridge.dart';
import 'package:diting_android/state/ca_inspection_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// CA certificate settings (upstream `CaCertificateSettingsScreen`). State comes from
/// `CaCertificateService.inspect()`: `available`, `installed` and `fingerprintSha256`,
/// never hard-coded.
class CaCertificatePage extends ConsumerWidget {
  const CaCertificatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(caCertificateStateProvider);
    final state = asyncState.value;
    // The first inspect loads the Go engine and may take hundreds of milliseconds, so a
    // "checking" row shows meanwhile rather than a fake "not installed".
    if (state == null) {
      return CommonScaffold(
        title: context.l10n.caCertTitle,
        body: const Center(child: CommonCircleLoading.page()),
      );
    }
    final statusTitle = switch ((state.available, state.installed)) {
      (false, _) => context.l10n.caCertStatusMissing,
      (true, false) => context.l10n.caCertStatusUntrusted,
      (true, true) => context.l10n.caCertStatusTrusted,
    };
    final fingerprint = state.fingerprintSha256;
    final pem = state.pem;
    return CommonScaffold(
      title: context.l10n.caCertTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.caCertSectionStatus,
            items: [
              ListItem(
                leading: GlyphIcon(
                  state.ready ? AppGlyphs.verified : AppGlyphs.warning,
                  size: 20,
                ),
                title: Text(context.l10n.caCertRootStatus),
                subtitle: Text(statusTitle),
                trailing: Text(
                  state.ready ? context.l10n.caCertVerified : context.l10n.caCertUnverified,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ),
              if (state.error case final error?)
                ListItem(
                  leading: GlyphIcon(
                    AppGlyphs.warning,
                    size: 20,
                    color: context.colorScheme.error,
                  ),
                  title: Text(context.l10n.caCertReadFailed),
                  subtitle: Text(error),
                ),
            ],
            footer: context.l10n.caCertStatusFooter,
          ),
          generateSection(
            title: context.l10n.caCertSectionActions,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.info),
                title: Text(context.l10n.caCertGuide),
                subtitle: Text(context.l10n.caCertGuideSubtitle),
                onTap: () => context.push('/hub/https-inspection/ca/guide'),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.upload),
                title: Text(context.l10n.caCertInstall),
                subtitle: Text(context.l10n.caCertInstallSubtitle),
                trailing: Text(
                  state.installed ? context.l10n.caCertInstalled : context.l10n.caCertNotInstalled,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
                onTap: () => _install(context, ref, state),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.export),
                title: Text(context.l10n.caCertSaveToDownloads),
                subtitle: Text(context.l10n.caCertSaveToDownloadsSubtitle),
                onTap: () => _saveToDownloads(context, ref),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.key),
                title: Text(context.l10n.caCertFingerprint),
                subtitle: Text(
                  fingerprint == null ? context.l10n.caCertNoFingerprint : context.l10n.caCertFingerprintSubtitle,
                ),
                onTap: fingerprint == null
                    ? null
                    : () => _showFingerprint(context, fingerprint),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.copy),
                title: Text(context.l10n.caCertViewPem),
                subtitle: Text(context.l10n.caCertViewPemSubtitle),
                onTap: pem == null ? null : () => _showPem(context, pem),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.caCertSectionManage,
            items: [
              ListItem(
                leading: GlyphIcon(
                  AppGlyphs.refresh,
                  color: context.colorScheme.error,
                ),
                title: Text(
                  context.l10n.caCertRegenerate,
                  style: TextStyle(color: context.colorScheme.error),
                ),
                subtitle: Text(context.l10n.caCertRegenerateSubtitle),
                onTap: () => _regenerate(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Hands the staged PEM to the system certificate installer through the bridge. Android has no
  /// silent install, and since Android 11 the installer only points back at the settings screen, so
  /// the .crt is also dropped into Download first: that file is what the manual path needs.
  Future<void> _install(
    BuildContext context,
    WidgetRef ref,
    CaCertificateState state,
  ) async {
    if (!state.available || state.pem == null) {
      _toast(context, context.l10n.caCertNoCertificate);
      return;
    }
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.caCertInstall,
        child: Text(context.l10n.caCertInstallDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonContinue),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final notifier = ref.read(caCertificateStateProvider.notifier);
    final saved = await notifier.saveToDownloads();
    if (!context.mounted) {
      return;
    }
    final result = await notifier.install();
    if (!context.mounted) {
      return;
    }
    final hint = saved.saved
        ? context.l10n.caCertSavedTo(
            saved.name ?? context.l10n.caCertDownloadsDir,
          )
        : context.l10n.caCertSaveFailed(
            saved.error ?? context.l10n.commonUnknownReason,
          );
    _toast(
      context,
      '${switch (result.target) {
        CaInstallTarget.installer => context.l10n.caCertOpenedInstaller,
        CaInstallTarget.settings => context.l10n.caCertOpenedSettings,
        CaInstallTarget.none => result.error ?? context.l10n.caCertInstallerUnavailable,
      }}$hint${context.l10n.caCertManualHint}',
    );
    await notifier.refresh();
  }

  /// Fallback for ROMs without a certificate installer: writes the PEM where the user can pick it.
  Future<void> _saveToDownloads(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(caCertificateStateProvider.notifier)
        .saveToDownloads();
    if (!context.mounted) {
      return;
    }
    _toast(
      context,
      result.saved
          ? context.l10n.caCertSavedHint(
              result.name ?? context.l10n.caCertDownloadsDir,
            )
          : result.error ?? context.l10n.caCertDownloadsFailed,
    );
  }

  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.caCertRegenerateTitle,
        destructive: true,
        child: Text(context.l10n.caCertRegenerateBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.caCertRegenerateAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final next = await ref
        .read(caCertificateStateProvider.notifier)
        .regenerate();
    if (!context.mounted) {
      return;
    }
    _toast(
      context,
      next.error != null
          ? context.l10n.caCertGenerateFailed(next.error!)
          : context.l10n.caCertGenerated,
    );
  }

  Future<void> _showFingerprint(BuildContext context, String fingerprint) {
    return showFloatingDialog<void>(
      context: context,
      child: CommonDialog(
        title: context.l10n.caCertFingerprintTitle,
        child: SelectableText(
          fingerprint,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(fontFeatures: appTabularFigures, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: fingerprint));
              if (context.mounted) {
                Navigator.of(context).pop();
                _toast(context, context.l10n.caCertFingerprintCopied);
              }
            },
            child: Text(context.l10n.commonCopy),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.uiClose),
          ),
        ],
      ),
    );
  }

  Future<void> _showPem(BuildContext context, String pem) {
    return showFloatingDialog<void>(
      context: context,
      child: CommonDialog(
        title: context.l10n.caCertPemTitle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: SelectableText(
              pem,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(fontFeatures: appTabularFigures, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: pem));
              if (context.mounted) {
                Navigator.of(context).pop();
                _toast(context, context.l10n.caCertPemCopied);
              }
            },
            child: Text(context.l10n.commonCopy),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.uiClose),
          ),
        ],
      ),
    );
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class CaCertificateGuidePage extends StatelessWidget {
  const CaCertificateGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.caCertGuideTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.caCertWhyTitle,
            items: [
              _GuideItem(context.l10n.caCertWhyBody),
            ],
          ),
          generateSection(
            title: context.l10n.caCertStepsTitle,
            items: [
              _GuideItem(context.l10n.caCertStep1),
              _GuideItem(context.l10n.caCertStep2),
              _GuideItem(context.l10n.caCertStep3),
              _GuideItem(context.l10n.caCertStep4),
            ],
          ),
          generateSection(
            title: context.l10n.caCertWhichAppsTitle,
            items: [
              _GuideItem(context.l10n.caCertWhichAppsBody),
              _GuideWarning(context.l10n.caCertWhichAppsWarning),
            ],
          ),
          generateSection(
            title: context.l10n.caCertRiskTitle,
            items: [
              _GuideWarning(context.l10n.caCertRiskWarning),
              _GuideItem(context.l10n.caCertRiskPinning),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  const _GuideItem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppTextStyle.body.of(context).copyWith(height: 1.6),
      ),
    );
  }
}

class _GuideWarning extends StatelessWidget {
  const _GuideWarning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CommonCard(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.error, height: 1.5),
        ),
      ),
    );
  }
}
