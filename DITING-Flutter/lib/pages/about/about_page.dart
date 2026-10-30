/// About page, merged with the former update & support page. The layout follows FlClash's
/// `lib/views/about.dart`: centred hero, version/licence pills, one check-update bar, then grouped
/// rows. Update state renders inline under the bar instead of a separate card.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/pages/hub/recognition_pages.dart';
import 'package:diting/pages/system/app_info.dart';
import 'package:diting/pages/system/disclaimer_page.dart';
import 'package:diting/state/app_version_provider.dart';
import 'package:diting/state/settings_providers.dart';
import 'package:diting/state/system_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/note_card.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:diting/widgets/status_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                glyph: AppGlyphs.code,
                title: context.l10n.aboutProject,
                label: projectRepositoryUrl.replaceFirst('https://', ''),
                url: projectRepositoryUrl,
              ),
              _LinkRow(
                glyph: AppGlyphs.send,
                title: context.l10n.aboutJoinQq,
                label: context.l10n.aboutQqGroup(qqGroupNumber),
                url: qqGroupUri,
              ),
              _LinkRow(
                glyph: AppGlyphs.star,
                title: context.l10n.aboutSponsor,
                label: sponsorReadmeUrl.replaceFirst('https://', ''),
                url: sponsorReadmeUrl,
              ),
            ],
          ),
          generateSection(
            title: context.l10n.aboutCredits,
            items: [
              _LinkRow(
                glyph: AppGlyphs.palette,
                title: '       ',
                label: context.l10n.aboutCreditsUi,
                url: flClashRepositoryUrl,
              ),
              _LinkRow(
                glyph: AppGlyphs.vpn,
                title: 'blockads-android',
                label: context.l10n.aboutCreditsCore,
                url: blockAdsRepositoryUrl,
              ),
            ],
            footer:
                context.l10n.aboutCreditsBody,
          ),
          generateSection(
            title: context.l10n.aboutSettings,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.clock),
                title: Text(context.l10n.aboutStartupCheck),
                subtitle: Text(
                  disableStartupCheck ? context.l10n.aboutStartupCheckOn : context.l10n.aboutStartupCheckOff,
                ),
                value: disableStartupCheck,
                onChanged: (value) =>
                    ref.read(startupUpdateCheckProvider.notifier).toggle(value),
              ),
              ListItem.next(
                leading: const GlyphIcon(AppGlyphs.gavel),
                title: Text(context.l10n.aboutDisclaimerEntry),
                subtitle: Text(context.l10n.aboutDisclaimerEntryBody),
                // Acceptance happens in the first-run dialog; this only re-reads it.
                widget: const DisclaimerPage(),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.aboutOtherContributors,
            items: [
              ListItem.next(
                leading: const GlyphIcon(AppGlyphs.verified),
                title: Text(context.l10n.aboutSponsorList),
                subtitle: Text(context.l10n.aboutSponsorListBody),
                widget: const SponsorListPage(),
              ),
              ListItem.next(
                leading: const GlyphIcon(AppGlyphs.account),
                title: Text(context.l10n.aboutBuilderList),
                subtitle: Text(context.l10n.aboutBuilderListBody),
                widget: const CoBuildersPage(),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Install through the system installer; failures are reported, usually a missing install
  /// permission.
  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await ref.read(updateProvider.notifier).install();
    if (!context.mounted) return;
    if (!ok) {
      final reason = ref.read(updateProvider).error ?? context.l10n.aboutInstallerFailed;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(reason),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }
}

/// Centred hero: app icon, name, version and licence pills, description and the update bar.
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
    // The brand mark ships in both modes: #FAF8F9/#007AFE for light, #1F1F22/#2E83FF for dark.
    final logoAsset = colorScheme.brightness == Brightness.dark
        ? 'assets/images/icon_dark.png'
        : 'assets/images/icon.png';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: context.raisedSurfaceLevel.colorOf(colorScheme),
              shape: AppShape.all(AppCorner.fit(_logoSize)),
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
          Text(context.l10n.aboutAppName, style: AppTextStyle.title2.of(context, emphasized: true)),
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
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          TonalButton(
            size: TonalButtonSize.bar,
            glyph: AppGlyphs.sync,
            label: stage == UpdateStage.checking ? context.l10n.aboutChecking : context.l10n.aboutCheckUpdate,
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
                    ? AppGlyphs.check
                    : AppGlyphs.cloudDownload,
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
                style: context.listCaptionStyle.copyWith(color: caption.color),
              ),
            ),
        ],
      ),
    );
  }

  /// One status line under the bar; null while idle and clean, where the bar speaks for itself.
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
          if (update.error != null) '，${update.error}',
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

/// External link row: square glyph badge, title, one-line target, open-external arrow.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.glyph,
    required this.title,
    required this.label,
    required this.url,
  });

  final Glyph glyph;
  final String title;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ListItem(
      leading: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.raisedSurfaceLevel.colorOf(colorScheme),
          shape: AppShape.md,
        ),
        child: SizedBox.square(
          dimension: 40,
          child: Center(
            child: GlyphIcon(
              glyph,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      title: Text(title),
      subtitle: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const GlyphIcon(AppGlyphs.openExternal),
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
