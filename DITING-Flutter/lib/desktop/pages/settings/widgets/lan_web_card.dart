/// The LAN web console card: the master switch, the port, the URLs to open, the firewall rule and the
/// admin credential.
///
/// The old desktop console's `LanWebCard.vue` is the blueprint. The switch sends
/// `configureFirewall: true`, as the console did, so turning the console on also asks for the rule;
/// whether the host actually has a firewall manager is the service's answer, not a guess here.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_web_models.dart';
import 'package:diting/desktop/data/api/desktop_web_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class LanWebCard extends ConsumerStatefulWidget {
  const LanWebCard({super.key, required this.status, required this.saving});

  final DesktopWebStatus status;
  final bool saving;

  @override
  ConsumerState<LanWebCard> createState() => _LanWebCardState();
}

class _LanWebCardState extends ConsumerState<LanWebCard> {
  late final _port = TextEditingController(text: '${widget.status.port}');
  bool _portInvalid = false;

  @override
  void didUpdateWidget(LanWebCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.port == widget.status.port) return;
    _port.text = '${widget.status.port}';
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _configure(bool enabled, {int? port}) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopWebProvider.notifier)
        .configure(enabled: enabled, port: port ?? widget.status.port);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (enabled ? l10n.desktopLanWebOn : l10n.desktopLanWebOff)
          : l10n.desktopLanWebFailed(error.message),
    );
  }

  void _savePort() {
    final port = int.tryParse(_port.text);
    if (port == null || port < 1 || port > 65535) {
      setState(() => _portInvalid = true);
      return;
    }
    setState(() => _portInvalid = false);
    unawaited(_configure(widget.status.enabled, port: port));
  }

  Future<void> _setFirewall(bool allowed) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopWebProvider.notifier)
        .setFirewall(allowed);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (allowed ? l10n.desktopLanWebFirewallOn : l10n.desktopLanWebFirewallOff)
          : l10n.desktopLanWebFailed(error.message),
    );
  }

  Future<void> _editPassword() async {
    final l10n = context.l10n;
    final status = widget.status;
    final draft = await showFloatingDialog<({String oldPassword, String newPassword})>(
      context: context,
      child: _PasswordDialog(status: status),
    );
    if (draft == null || !mounted) return;
    final error = await ref
        .read(desktopWebProvider.notifier)
        .setPassword(
          username: status.username,
          oldPassword: draft.oldPassword,
          newPassword: draft.newPassword,
          initialized: status.initialized,
        );
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null ? l10n.desktopLanWebPasswordSaved : l10n.desktopLanWebFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = widget.status;
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopLanWebTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.link,
            title: l10n.desktopLanWebTitle,
            leading: [
              DashboardChip(
                label: status.enabled
                    ? l10n.desktopLanWebOpen
                    : l10n.desktopLanWebLocal,
                tone: status.enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: status.enabled,
              ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardSwitch(
                  value: status.enabled,
                  semanticLabel: l10n.desktopLanWebTitle,
                  onChanged: (value) => unawaited(_configure(value)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            status.enabled
                ? l10n.desktopLanWebEnabledBody
                : l10n.desktopLanWebDisabledBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (status.enabled) ...[
            const SizedBox(height: 12),
            Text(
              l10n.desktopLanWebUrls,
              style: DashboardText.rowTitle(context),
            ),
            const SizedBox(height: 4),
            if (status.webUrls.isEmpty)
              Text(
                l10n.desktopLanWebNoUrls,
                style: DashboardText.label(context),
              )
            else
              for (final url in status.webUrls) _UrlRow(url: url),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l10n.desktopLanWebPort,
                    ),
                    style: AppTextStyle.callout.of(context).toMonospace,
                    onChanged: (_) => setState(() => _portInvalid = false),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: saving ? null : _savePort,
                  child: Text(l10n.desktopLanWebSavePort),
                ),
              ],
            ),
            if (_portInvalid) ...[
              const SizedBox(height: 6),
              Text(
                l10n.desktopLanWebPortInvalid,
                style: DashboardText.label(
                  context,
                  color: context.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (status.firewallSupported)
              FilterToggleRow(
                title: l10n.desktopLanWebFirewall,
                body: l10n.desktopLanWebFirewallBody,
                value: status.firewallAllowed,
                onChanged: saving
                    ? null
                    : (value) => unawaited(_setFirewall(value)),
              )
            else
              Text(
                l10n.desktopLanWebNoFirewall,
                style: DashboardText.label(context),
              ),
          ],
          const SizedBox(height: 10),
          _CredentialsRow(
            username: status.username,
            initialized: status.initialized,
            saving: saving,
            onEdit: () => unawaited(_editPassword()),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopLanWebFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

class _UrlRow extends StatelessWidget {
  const _UrlRow({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        spacing: 6,
        children: [
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context).toMonospace,
            ),
          ),
          SizedBox(
            height: 28,
            child: DashboardIconButton(
              glyph: AppGlyphs.copy,
              tooltip: MaterialLocalizations.of(context).copyButtonLabel,
              size: 28,
              glyphSize: 15,
              onPressed: () => Clipboard.setData(ClipboardData(text: url)),
            ),
          ),
          SizedBox(
            height: 28,
            child: DashboardIconButton(
              glyph: AppGlyphs.openExternal,
              tooltip: l10n.desktopEncryptedOpenUrl,
              size: 28,
              glyphSize: 15,
              onPressed: () => launchUrl(Uri.parse(url)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialsRow extends StatelessWidget {
  const _CredentialsRow({
    required this.username,
    required this.initialized,
    required this.saving,
    required this.onEdit,
  });

  final String username;
  final bool initialized;
  final bool saving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                l10n.desktopLanWebCredentials,
                style: DashboardText.rowTitle(context),
              ),
              Text(
                username.isEmpty
                    ? l10n.desktopLanWebNoUser
                    : l10n.desktopLanWebUser(username),
                style: DashboardText.label(context).toMonospace,
              ),
              Text(
                initialized
                    ? l10n.desktopLanWebProtected
                    : l10n.desktopLanWebUnprotected,
                style: DashboardText.label(context),
              ),
            ],
          ),
          TextButton(
            onPressed: saving ? null : onEdit,
            child: Text(
              initialized
                  ? l10n.desktopLanWebChangePassword
                  : l10n.desktopLanWebSetPassword,
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.status});

  final DesktopWebStatus status;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = context.l10n;
    if (_new.text.isEmpty) {
      setState(() => _error = l10n.desktopLanWebPasswordRequired);
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = l10n.desktopLanWebPasswordMismatch);
      return;
    }
    if (widget.status.initialized && _old.text.isEmpty) {
      setState(() => _error = l10n.desktopLanWebOldRequired);
      return;
    }
    popFloatingDialog(context, (
      oldPassword: _old.text,
      newPassword: _new.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final initialized = widget.status.initialized;
    return CommonDialog(
      title: initialized
          ? l10n.desktopLanWebChangePassword
          : l10n.desktopLanWebSetPassword,
      hasFields: true,
      width: 460,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(l10n.desktopLanWebPasswordSave),
        ),
      ],
      child: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              initialized
                  ? l10n.desktopLanWebChangeBody(widget.status.username)
                  : l10n.desktopLanWebSetupBody(widget.status.username),
              style: DashboardText.label(context),
            ),
            if (initialized)
              TextField(
                controller: _old,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.desktopLanWebOldPassword,
                ),
              ),
            TextField(
              controller: _new,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.desktopLanWebNewPassword,
              ),
            ),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.desktopLanWebConfirmPassword,
              ),
            ),
            if (_error case final error?)
              Text(
                error,
                style: DashboardText.label(
                  context,
                  color: context.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
