/// The LAN console's host-side access: the firewall rule and the admin credential.
///
/// The old desktop console's `LanWebCard.vue` keeps these under the URLs; here they are their own card.
/// The firewall switch saves on the spot and reports whether the host even has a manager for it; the
/// password is set through a dialog, because a credential is not a field to leave on screen.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_web_models.dart';
import 'package:diting_desktop/data/api/desktop_web_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class LanWebAccessCard extends ConsumerWidget {
  const LanWebAccessCard({
    super.key,
    required this.status,
    required this.saving,
  });

  final DesktopWebStatus status;
  final bool saving;

  Future<void> _setFirewall(BuildContext context, WidgetRef ref, bool allowed) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopWebProvider.notifier)
        .setFirewall(allowed);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (allowed
                ? l10n.desktopLanWebFirewallOn
                : l10n.desktopLanWebFirewallOff)
          : l10n.desktopLanWebFailed(error.message),
    );
  }

  Future<void> _editPassword(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final draft =
        await showFloatingDialog<({String oldPassword, String newPassword})>(
          context: context,
          child: _PasswordDialog(status: status),
        );
    if (draft == null || !context.mounted) return;
    final error = await ref
        .read(desktopWebProvider.notifier)
        .setPassword(
          username: status.username,
          oldPassword: draft.oldPassword,
          newPassword: draft.newPassword,
          initialized: status.initialized,
        );
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopLanWebPasswordSaved
          : l10n.desktopLanWebFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final saving = this.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopLanWebAccessTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.lock,
            title: l10n.desktopLanWebAccessTitle,
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopLanWebAccessBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          if (status.firewallSupported)
            FilterToggleRow(
              title: l10n.desktopLanWebFirewall,
              body: l10n.desktopLanWebFirewallBody,
              value: status.firewallAllowed,
              onChanged: saving
                  ? null
                  : (value) => unawaited(
                      _setFirewall(context, ref, value),
                    ),
            )
          else
            Text(
              l10n.desktopLanWebNoFirewall,
              style: DashboardText.label(context),
            ),
          const SizedBox(height: 10),
          _CredentialsRow(
            username: status.username,
            initialized: status.initialized,
            saving: saving,
            onEdit: () => unawaited(_editPassword(context, ref)),
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
