/// N6 网络诊断：DNS 泄漏检测与 Captive Portal 识别。
///
/// The verdicts are Rust kernels ([RustLeakCore], [RustCaptiveCore]); this page only runs the
/// probes, shows the three-state result and, for a portal, offers to open the login page.
library;

import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_android/state/network_diagnostics_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class NetworkDiagnosticsPage extends ConsumerWidget {
  const NetworkDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(networkDiagnosticsProvider);
    final notifier = ref.read(networkDiagnosticsProvider.notifier);
    final l10n = context.l10n;

    return CommonScaffold(
      title: l10n.networkDiagnosticsTitle,
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.networkDiagnosticsIntro),
          if (state.error != null)
            _ErrorNotice(text: l10n.networkDiagnosticsFailed),
          _DiagnosticsSection(
            title: l10n.dnsLeakSection,
            rows: [
              if (state.leak != null)
                _VerdictItem(
                  icon: state.leak!.status == 'leak'
                      ? AppGlyphs.block
                      : AppGlyphs.checkCircle,
                  error: state.leak!.status == 'leak',
                  title: _leakLabel(context, state.leak!.status),
                  detail: _leakReason(context, state.leak!.reason),
                ),
            ],
            action: _ActionButton(
              label: l10n.dnsLeakRun,
              glyph: AppGlyphs.speed,
              busy: state.leakBusy,
              onPressed: notifier.runLeakCheck,
            ),
          ),
          _DiagnosticsSection(
            title: l10n.captiveSection,
            rows: [
              if (state.captive != null)
                _VerdictItem(
                  icon: state.captive!.state == 'portal'
                      ? AppGlyphs.wifiOff
                      : AppGlyphs.checkCircle,
                  error: state.captive!.state == 'portal',
                  title: _captiveLabel(context, state.captive!.state),
                  detail: state.captive!.portalUrl ?? '',
                ),
            ],
            action: _ActionButton(
              label: l10n.captiveRun,
              glyph: AppGlyphs.wifi,
              busy: state.captiveBusy,
              onPressed: notifier.runCaptiveCheck,
            ),
          ),
          if (state.captive?.portalUrl != null)
            _ActionButton(
              label: l10n.captiveOpenPortal,
              glyph: AppGlyphs.openExternal,
              busy: false,
              onPressed: () => launchUrl(
                Uri.parse(state.captive!.portalUrl!),
                mode: LaunchMode.externalApplication,
              ),
            ),
          generateSection(
            title: l10n.hubModuleMore,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.target),
                title: Text(l10n.devIpQuality),
                subtitle: Text(l10n.devIpQualityBody),
                onTap: () => context.push(SystemPaths.ipQuality),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _leakLabel(BuildContext context, String status) =>
      switch (status) {
        'pass' => context.l10n.dnsLeakPass,
        'leak' => context.l10n.dnsLeakLeak,
        _ => context.l10n.dnsLeakUnknown,
      };

  static String _leakReason(BuildContext context, String reason) =>
      switch (reason) {
        'bypass_upstream' => context.l10n.dnsLeakReasonBypass,
        'proxied_without_identity' => context.l10n.dnsLeakReasonProxied,
        'exit_mismatch' => context.l10n.dnsLeakReasonMismatch,
        'plaintext_dns_egress' => context.l10n.dnsLeakReasonPlaintext,
        _ => context.l10n.dnsLeakReasonInsufficient,
      };

  static String _captiveLabel(BuildContext context, String state) =>
      switch (state) {
        'open' => context.l10n.captiveOpen,
        'portal' => context.l10n.captivePortal,
        _ => context.l10n.captiveUnknown,
      };
}

/// A diagnostics block: a section header, the optional verdict card, then the run action.
///
/// The action is a **sibling** of the rows — never an item inside the card. A non-row child in a
/// card group leaves the preceding rows with square bottom corners and a stray divider, which is
/// what made the old layout look like a clipped card with a button floating below it.
class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({
    required this.title,
    required this.rows,
    required this.action,
  });

  final String title;
  final List<Widget> rows;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListHeader(title: title),
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: generateGroup(rows),
          ),
        action,
      ],
    );
  }
}

class _VerdictItem extends StatelessWidget {
  const _VerdictItem({
    required this.icon,
    required this.error,
    required this.title,
    required this.detail,
  });

  final Glyph icon;
  final bool error;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? context.colorScheme.error
        : context.colorScheme.success;
    return ListItem(
      leading: GlyphIcon(icon, color: color),
      title: Text(title),
      subtitle: detail.isEmpty ? null : Text(detail),
    );
  }
}

/// A full-width section action. Kept outside the card group so the card keeps its rounded shape;
/// the tonal fill matches the actions on the other tool pages.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.glyph,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final Glyph glyph;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TonalButton(
        glyph: busy ? null : glyph,
        label: label,
        size: TonalButtonSize.section,
        onPressed: busy ? null : onPressed,
      ),
    );
  }
}

/// A page-level failure, in the error palette rather than the neutral intro card surface.
class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        isError: true,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            GlyphIcon(AppGlyphs.error, size: 18, color: colorScheme.error),
            Expanded(
              child: Text(
                text,
                style: context.listCaptionStyle.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
