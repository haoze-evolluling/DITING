/// The login page's change-password form.
///
/// The old console kept this in `LoginModal.vue`, opened from the LAN console card; the web login page
/// itself only offered login and first-run setup. The service exposes `/auth/password`, which needs the
/// current password from a remote browser, so the same credential can be rotated from the login page —
/// and the service invalidates every other session when it succeeds.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_auth_providers.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class LoginChangePasswordCard extends ConsumerStatefulWidget {
  const LoginChangePasswordCard({
    super.key,
    required this.username,
    required this.onBack,
  });

  final String username;

  /// Back to the login form; the credential has already changed by then.
  final VoidCallback onBack;

  @override
  ConsumerState<LoginChangePasswordCard> createState() =>
      _LoginChangePasswordCardState();
}

class _LoginChangePasswordCardState
    extends ConsumerState<LoginChangePasswordCard> {
  final _old = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _old.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (_old.text.isEmpty) {
      setState(() => _error = l10n.desktopLoginOldPasswordRequired);
      return;
    }
    if (_password.text.length < 4) {
      setState(() => _error = l10n.desktopLoginPasswordTooShort);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = l10n.desktopLoginPasswordMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    final error = await ref
        .read(desktopAuthProvider.notifier)
        .changePassword(
          username: widget.username,
          oldPassword: _old.text,
          newPassword: _password.text,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _success = l10n.desktopLoginChangeSuccess;
        _old.clear();
        _password.clear();
        _confirm.clear();
      } else {
        _error = error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.desktopLoginChangePassword,
          style: AppTextStyle.title2.of(context, emphasized: true),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.desktopLoginChangeSubtitle,
          style: DashboardText.label(context),
        ),
        const SizedBox(height: 14),
        if (_error case final error?) ...[
          Text(
            error,
            style: DashboardText.label(context, color: colorScheme.error),
          ),
          const SizedBox(height: 10),
        ],
        if (_success case final success?) ...[
          Text(
            success,
            style: DashboardText.label(context, color: colorScheme.success),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _old,
          enabled: !_busy,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: l10n.desktopLoginOldPasswordLabel,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: l10n.desktopLoginNewPasswordLabel,
            suffixIcon: IconButton(
              tooltip: _obscure
                  ? l10n.desktopLoginShowPassword
                  : l10n.desktopLoginHidePassword,
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: GlyphIcon(
                _obscure ? AppGlyphs.eyeOff : AppGlyphs.eye,
                size: 18,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _confirm,
          enabled: !_busy,
          obscureText: _obscure,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
            labelText: l10n.desktopLoginConfirmLabel,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CommonCircleLoading(),
                )
              : Text(l10n.desktopLoginChangeSubmit),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _busy ? null : widget.onBack,
          child: Text(l10n.desktopLoginBackToSignIn),
        ),
      ],
    );
  }
}
