library;

import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_android/state/network_diagnostics_providers.dart';
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
    final leak = state.leak;
    final captive = state.captive;
    final portalUrl = captive?.portalUrl;

    return CommonScaffold(
      title: l10n.networkDiagnosticsTitle,
      body: PageBody(
        children: [
          if (state.error != null)
            _ErrorNotice(text: l10n.networkDiagnosticsFailed),
          _DiagnosticsSection(
            title: l10n.dnsLeakSection,
            rows: [
              if (leak != null)
                _VerdictItem(
                  icon: leak.status == 'leak'
                      ? TablerIcons.ban
                      : TablerIcons.circle_check,
                  error: leak.status == 'leak',
                  title: _leakLabel(context, leak.status),
                  detail: _leakReason(context, leak.reason),
                ),
            ],
            action: _ActionButton(
              label: l10n.dnsLeakRun,
              glyph: TablerIcons.gauge,
              busy: state.leakBusy,
              onPressed: notifier.runLeakCheck,
            ),
          ),
          _DiagnosticsSection(
            title: l10n.captiveSection,
            rows: [
              if (captive != null)
                _VerdictItem(
                  icon: captive.state == 'portal'
                      ? TablerIcons.wifi_off
                      : TablerIcons.circle_check,
                  error: captive.state == 'portal',
                  title: _captiveLabel(context, captive.state),
                  detail: captive.portalUrl ?? '',
                ),
            ],
            action: _ActionButton(
              label: l10n.captiveRun,
              glyph: TablerIcons.wifi,
              busy: state.captiveBusy,
              onPressed: notifier.runCaptiveCheck,
            ),
          ),
          if (portalUrl != null)
            _ActionButton(
              label: l10n.captiveOpenPortal,
              glyph: TablerIcons.external_link,
              busy: false,
              onPressed: () => launchUrl(
                Uri.parse(portalUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          generateSection(
            title: l10n.hubModuleMore,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.target),
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

  final IconData icon;
  final bool error;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? context.colorScheme.error
        : context.colorScheme.success;
    return ListItem(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: detail.isEmpty ? null : Text(detail),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.glyph,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData glyph;
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
            Icon(TablerIcons.alert_circle, size: 18, color: colorScheme.error),
            Expanded(
              child: Text(
                text,
                style: AppTextRole.supportingText
                    .of(context)
                    .copyWith(color: colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
