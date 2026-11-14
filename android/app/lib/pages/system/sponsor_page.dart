/// Sponsor page, aligned with `ui/SponsorScreen.kt`; QR codes come from the README.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/system/app_info.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class SponsorPage extends StatelessWidget {
  const SponsorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.aboutSponsor,
      body: PageBody(
        children: [
          const _SponsorHero(),
          const _PaymentSection(),
          generateSection(
            title: context.l10n.sponsorGithub,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.link),
                title: Text(context.l10n.sponsorReadme),
                subtitle: Text(
                  sponsorReadmeUrl.replaceFirst('https://', ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const GlyphIcon(AppGlyphs.openExternal, size: 20),
                onTap: () => openLinkOrCopy(
                  context,
                  sponsorReadmeUrl,
                  context.l10n.sponsorReadmeCopied,
                ),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.sponsorThanks,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.verified,
                title: context.l10n.aboutSponsorList,
                subtitle: context.l10n.sponsorThanksBody,
                onPressed: () => context.push(HubPaths.sponsorList),
              ),
              NavEntryRow(
                glyph: AppGlyphs.account,
                title: context.l10n.aboutBuilderList,
                subtitle: context.l10n.sponsorBuildersBody,
                onPressed: () => context.push(HubPaths.coBuilders),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.sponsorUsage,
            items: [
              _BulletRow(text: context.l10n.sponsorUsageNewFeatures),
              _BulletRow(text: context.l10n.sponsorUsageBugs),
              _BulletRow(text: context.l10n.sponsorUsageTokens),
            ],
          ),
          generateSection(
            title: context.l10n.sponsorFreeWays,
            items: [
              _BulletRow(text: context.l10n.sponsorFreeStar),
              _BulletRow(text: context.l10n.sponsorFreeIssue),
              _BulletRow(text: context.l10n.sponsorFreePr),
              _BulletRow(text: context.l10n.sponsorFreeShare),
            ],
          ),
          ListFooter(text: context.l10n.sponsorFooter),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Header card: icon, title, description and tags. A card rather than bare text keeps the
/// header consistent with the app info page.
class _SponsorHero extends StatelessWidget {
  const _SponsorHero();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Row(
              spacing: 12,
              children: [
                IconBadge(
                  glyph: AppGlyphs.star,
                  size: 52,
                  glyphSize: 28,
                  color: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        context.l10n.sponsorSupportKicker,
                        style: AppTextStyle.caption2
                            .of(context)
                            .copyWith(
                              color: colorScheme.primary,
                              fontFeatures: appTabularFigures,
                            ),
                      ),
                      Text(
                        context.l10n.sponsorBuyDrink,
                        style: AppTextStyle.title2.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              context.l10n.sponsorNote,
              style: context.listSubtitleStyle,
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MetaChip(label: context.l10n.sponsorAlipay),
                MetaChip(label: context.l10n.sponsorWechat),
                MetaChip(label: context.l10n.sponsorNickname),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentSection extends StatelessWidget {
  const _PaymentSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListHeader(title: context.l10n.sponsorScan),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: _PaymentCard(
                  asset: 'packages/diting_shared/assets/pay/alipay_code.webp',
                  label: context.l10n.sponsorAlipay,
                  glyph: AppGlyphs.qrCode,
                ),
              ),
              Expanded(
                child: _PaymentCard(
                  asset: 'packages/diting_shared/assets/pay/wechatpay_code.webp',
                  label: context.l10n.sponsorWechat,
                  glyph: AppGlyphs.qrCode,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One QR code card: white background, since a code needs a light surround to scan, plus its name.
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.asset,
    required this.label,
    required this.glyph,
  });

  final String asset;
  final String label;
  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      padding: EdgeInsets.zero,
      onPressed: () => _showFullscreen(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          spacing: 8,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // A code needs a static light background and must not follow dark theme
                // inversion, or it cannot be scanned.
                child: ColoredBox(
                  color: Colors.white,
                  child: Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: GlyphIcon(AppGlyphs.qrCode, size: 32),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                GlyphIcon(glyph, size: 16, color: context.colorScheme.primary),
                Text(label, style: context.listSubtitleStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFullscreen(BuildContext context) {
    showFloatingDialog<void>(
      context: context,
      child: CommonDialog(
        title: context.l10n.sponsorQrCode(label),
        width: 320,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.sponsorClose),
          ),
        ],
        child: Column(
          spacing: 12,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: Colors.white,
                child: Image.asset(asset, fit: BoxFit.contain),
              ),
            ),
            Text(
              context.l10n.sponsorNoteShort,
              style: context.listCaptionStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A bulleted list row matching the legacy `SponsorList`.
class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: Text(
        '•',
        style: AppTextStyle.body
            .of(context)
            .copyWith(color: context.colorScheme.primary),
      ),
      title: Text(text),
    );
  }
}
