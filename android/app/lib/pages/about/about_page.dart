library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/system/app_info.dart';
import 'package:diting_android/pages/system/disclaimer_page.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_android/state/app_version_provider.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/system_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_android/widgets/note_card.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:diting_android/widgets/status_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateProvider);
    final notifier = ref.read(updateProvider.notifier);
    final disableStartupCheck = ref.watch(startupUpdateCheckProvider);
    return CommonScaffold(
      title: context.l10n.aboutTitle,
      body: PageBody(
        children: [
          _AboutHero(
            version: ref.watch(appVersionProvider).name,
            update: update,
            onCheck: update.stage.isBusy ? null : notifier.check,
            onDownload: update.stage.isBusy ? null : notifier.download,
            onInstall: () => _install(context, ref),
          ),
          const SizedBox(height: 8),
          generateSection(
            title: context.l10n.aboutMore,
            items: [
              _LinkRow(
                glyph: TablerIcons.code,
                title: context.l10n.aboutProject,
                label: projectRepositoryUrl.replaceFirst('https://', ''),
                url: projectRepositoryUrl,
              ),
              _LinkRow(
                glyph: TablerIcons.send,
                title: context.l10n.aboutJoinQq,
                label: context.l10n.aboutQqGroup(qqGroupNumber),
                url: qqGroupUri,
              ),
            ],
          ),
          generateSection(
            title: context.l10n.aboutSupport,
            items: [
              NavEntryRow(
                glyph: TablerIcons.heart,
                title: context.l10n.hubSponsor,
                subtitle: context.l10n.hubSponsorDescription,
                onPressed: () => context.push(SystemPaths.sponsor),
              ),
              NavEntryRow(
                glyph: TablerIcons.star,
                title: context.l10n.aboutSponsorList,
                subtitle: context.l10n.aboutSponsorListBody,
                onPressed: () => context.push(HubPaths.sponsorList),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.aboutSettings,
            items: [
              ListItem.toggle(
                leading: const Icon(TablerIcons.clock),
                title: Text(context.l10n.aboutStartupCheck),
                subtitle: Text(
                  disableStartupCheck
                      ? context.l10n.aboutStartupCheckOn
                      : context.l10n.aboutStartupCheckOff,
                ),
                value: disableStartupCheck,
                onChanged: (value) =>
                    ref.read(startupUpdateCheckProvider.notifier).toggle(value),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.aboutCredits,
            items: [
              _LinkRow(
                glyph: TablerIcons.palette,
                title: '',
                label: context.l10n.aboutCreditsUi,
                url: flClashRepositoryUrl,
              ),
              _LinkRow(
                glyph: TablerIcons.shield_lock,
                title: 'blockads-android',
                label: context.l10n.aboutCreditsCore,
                url: blockAdsRepositoryUrl,
              ),
            ],
            footer: context.l10n.aboutCreditsBody,
          ),
          generateSection(
            title: context.l10n.aboutLegal,
            items: [
              ListItem.next(
                leading: const Icon(TablerIcons.gavel),
                title: Text(context.l10n.aboutDisclaimerEntry),
                subtitle: Text(context.l10n.aboutDisclaimerEntryBody),
                widget: const DisclaimerPage(),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(updateProvider.notifier).install();
    if (!context.mounted) return;
    if (!ok) {
      final reason =
          ref.read(updateProvider).error ?? context.l10n.aboutInstallerFailed;
      showAppSnack(
        context,
        reason,
        duration: const Duration(milliseconds: 2200),
      );
    }
  }
}

class _AboutHero extends StatelessWidget {
  const _AboutHero({
    required this.version,
    required this.update,
    required this.onCheck,
    required this.onDownload,
    required this.onInstall,
  });

  static const _logoSize = 96.0;
  static const _logoInset = 14.0;

  final String version;
  final UpdateState update;
  final VoidCallback? onCheck;
  final VoidCallback? onDownload;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final stage = update.stage;
    final logoAsset = colorScheme.brightness == Brightness.dark
        ? 'packages/diting_shared/assets/images/icon_dark.webp'
        : 'packages/diting_shared/assets/images/icon.webp';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: context.raisedSurfaceLevel.colorOf(colorScheme),
              shape: AppShape.standard,
            ),
            child: Padding(
              padding: const EdgeInsets.all(_logoInset),
              child: Image.asset(
                logoAsset,
                width: _logoSize - _logoInset * 2,
                height: _logoSize - _logoInset * 2,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.aboutAppName,
            style: AppTextRole.sectionTitle.of(context),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _Pill(
                label: 'v$version',
                color: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              _Pill(
                label: 'GPL-3.0',
                color: context.raisedSurfaceLevel.colorOf(colorScheme),
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              context.l10n.aboutTagline,
              textAlign: TextAlign.center,
              style: AppTextRole.body
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 20),
          TonalButton(
            size: TonalButtonSize.bar,
            glyph: TablerIcons.rotate_clockwise,
            label: stage == UpdateStage.checking
                ? context.l10n.aboutChecking
                : context.l10n.aboutCheckUpdate,
            onPressed: onCheck,
          ),
          if (stage == UpdateStage.downloading ||
              stage == UpdateStage.downloaded)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _DownloadProgress(state: update),
            ),
          if (stage == UpdateStage.available ||
              stage == UpdateStage.downloading ||
              stage == UpdateStage.downloaded)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TonalButton(
                size: TonalButtonSize.section,
                glyph: stage == UpdateStage.downloaded
                    ? TablerIcons.check
                    : TablerIcons.cloud_download,
                label: switch (stage) {
                  UpdateStage.downloading => context.l10n.aboutDownloading,
                  UpdateStage.downloaded => context.l10n.aboutInstall,
                  _ => context.l10n.aboutDownload,
                },
                onPressed: stage == UpdateStage.downloaded
                    ? onInstall
                    : onDownload,
              ),
            ),
          if (_caption(context) case final caption?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                caption.text,
                textAlign: TextAlign.center,
                style: AppTextRole.supportingText
                    .of(context)
                    .copyWith(color: caption.color),
              ),
            ),
        ],
      ),
    );
  }

  ({String text, Color color})? _caption(BuildContext context) {
    final colorScheme = context.colorScheme;
    final latest = update.info?.version;
    final current = update.currentVersion;
    return switch (update.stage) {
      UpdateStage.idle => switch (update.error) {
        final error? => (text: error, color: colorScheme.error),
        null => null,
      },
      UpdateStage.checking => (
        text: context.l10n.aboutCheckingRelease,
        color: colorScheme.onSurfaceVariant,
      ),
      UpdateStage.upToDate => (
        text: context.l10n.aboutUpToDate(
          current == null ? '' : context.l10n.aboutVersionSuffix(current),
        ),
        color: colorScheme.success,
      ),
      UpdateStage.available => (
        text: [
          context.l10n.aboutFoundVersion(latest ?? context.l10n.aboutNew),
          if (current != null) context.l10n.aboutCurrentSuffix(current),
          if (update.error != null) ' · ${update.error}',
        ].join(),
        color: update.error == null ? colorScheme.primary : colorScheme.error,
      ),
      UpdateStage.downloading || UpdateStage.downloaded => (
        text: context.l10n.aboutUpdatePackage(
          latest ?? context.l10n.aboutNewVersion,
        ),
        color: colorScheme.onSurfaceVariant,
      ),
    };
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.foregroundColor,
  });

  final String label;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: label,
      color: color,
      foregroundColor: foregroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.glyph,
    required this.title,
    required this.label,
    required this.url,
  });

  final IconData glyph;
  final String title;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: Icon(glyph),
      title: Text(title),
      subtitle: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(TablerIcons.external_link, size: 20),
      onTap: () =>
          openLinkOrCopy(context, url, context.l10n.aboutLinkCopyFallback(url)),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final done = state.stage == UpdateStage.downloaded;
    return ProgressLine(
      value: state.progress,
      minHeight: 8,
      color: done ? colorScheme.success : colorScheme.primary,
    );
  }
}
