library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_auth_providers.dart';
import 'package:diting_desktop/pages/about/desktop_about_links.dart';
import 'package:diting_desktop/pages/home/desktop_format.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopAboutPage extends ConsumerWidget {
  const DesktopAboutPage({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopSettingsLogout,
      body: l10n.desktopSettingsLogoutConfirm,
      confirmLabel: l10n.desktopSettingsLogout,
    );
    if (!confirmed || !context.mounted) return;
    final error = await ref.read(desktopAuthProvider.notifier).signOut();
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null ? l10n.desktopSettingsLogoutDone : error.message,
    );
  }

  Widget _linkRow(
    BuildContext context, {
    required Glyph glyph,
    required String title,
    required String label,
    required Future<void> Function() onTap,
  }) => ListItem(
    leading: GlyphIcon(glyph, size: 20),
    title: Text(title),
    subtitle: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: const GlyphIcon(AppGlyphs.openExternal, size: 18),
    onTap: () => unawaited(onTap()),
  );

  Widget _group(
    BuildContext context, {
    required String title,
    required List<Widget> rows,
    String? footer,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListHeader(title: title),
      generateGroup(rows),
      if (footer != null) ListFooter(text: footer),
    ],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = ref.watch(desktopStatusProvider).status?.version;
    final webConsole = ref.watch(desktopWebConsoleProvider);
    return CommonScaffold(
      title: l10n.aboutTitle,
      body: PageBody(
        children: [
          DesktopCardBoard(
            cards: [
              _AboutHero(version: version ?? ''),
              _group(
                context,
                title: l10n.desktopAboutProjectSection,
                rows: [
                  _linkRow(
                    context,
                    glyph: AppGlyphs.code,
                    title: l10n.aboutAppName,
                    label: projectRepositoryUrl.replaceFirst('https://', ''),
                    onTap: () => openDesktopLink(context, projectRepositoryUrl),
                  ),
                  _linkRow(
                    context,
                    glyph: AppGlyphs.send,
                    title: l10n.aboutJoinQq,
                    label: l10n.aboutQqGroup(qqGroupNumber),
                    onTap: () => openDesktopQqGroup(context),
                  ),
                ],
              ),
              _group(
                context,
                title: l10n.aboutSupport,
                rows: [
                  _linkRow(
                    context,
                    glyph: AppGlyphs.heart,
                    title: l10n.aboutSponsor,
                    label: sponsorReadmeUrl.replaceFirst('https://', ''),
                    onTap: () => openDesktopLink(context, sponsorReadmeUrl),
                  ),
                ],
              ),
              _group(
                context,
                title: l10n.aboutCredits,
                footer: l10n.aboutCreditsBody,
                rows: [
                  _linkRow(
                    context,
                    glyph: AppGlyphs.palette,
                    title: '',
                    label: l10n.aboutCreditsUi,
                    onTap: () => openDesktopLink(context, flClashRepositoryUrl),
                  ),
                  _linkRow(
                    context,
                    glyph: AppGlyphs.vpn,
                    title: 'blockads-android',
                    label: l10n.aboutCreditsCore,
                    onTap: () =>
                        openDesktopLink(context, blockAdsRepositoryUrl),
                  ),
                ],
              ),
              const _AboutDisclaimerCard(),
              if (webConsole)
                _group(
                  context,
                  title: l10n.desktopSettingsSessionSection,
                  rows: [
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.lock, size: 20),
                      title: Text(l10n.desktopSettingsLogout),
                      subtitle: Text(l10n.desktopSettingsLogoutBody),
                      trailing: const GlyphIcon(
                        AppGlyphs.chevronForward,
                        size: 18,
                      ),
                      onTap: () => unawaited(_signOut(context, ref)),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutHero extends StatelessWidget {
  const _AboutHero({required this.version});

  static const _logoSize = 72.0;
  static const _logoInset = 10.0;

  final String version;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final logoAsset = colorScheme.brightness == Brightness.dark
        ? 'packages/diting_shared/assets/images/icon_dark.webp'
        : 'packages/diting_shared/assets/images/icon.webp';
    return DashboardCard(
      semanticLabel: context.l10n.aboutAppName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: DecoratedBox(
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
          ),
          const SizedBox(height: 14),
          Text(
            context.l10n.aboutAppName,
            textAlign: TextAlign.center,
            style: AppTextRole.sectionTitle.of(context),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              DashboardChip(
                label: version.isEmpty ? desktopNoValue : 'v$version',
                tone: DashboardChipTone.ok,
                large: true,
              ),
              const DashboardChip(label: 'GPL-3.0', large: true),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.aboutTagline,
            textAlign: TextAlign.center,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

class _AboutDisclaimerCard extends StatelessWidget {
  const _AboutDisclaimerCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopAboutDisclaimerSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.gavel,
            title: l10n.desktopAboutDisclaimerSection,
          ),
          const SizedBox(height: 10),
          Text(l10n.agreementMessage, style: DashboardText.label(context)),
        ],
      ),
    );
  }
}
