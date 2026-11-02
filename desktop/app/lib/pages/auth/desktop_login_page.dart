/// The web console's login and first-run setup page, plus the wallpaper it renders.
///
/// The old desktop console's `views/LoginView.vue` is the blueprint: one card over an optional
/// background image, a lockout countdown, the theme and palette shortcuts, and the background editor.
/// Only the browser that loaded the console sees this page — the desktop window talks to the service
/// over loopback IPC and never authenticates.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_desktop/data/api/desktop_auth_providers.dart';
import 'package:diting_desktop/pages/auth/widgets/login_background_dialog.dart';
import 'package:diting_desktop/pages/auth/widgets/login_change_password_card.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopLoginPage extends ConsumerStatefulWidget {
  const DesktopLoginPage({super.key});

  @override
  ConsumerState<DesktopLoginPage> createState() => _DesktopLoginPageState();
}

class _DesktopLoginPageState extends ConsumerState<DesktopLoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _success;
  int _lockout = 0;
  Timer? _lockoutTimer;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(desktopLoginBackgroundProvider.notifier).load());
    final auth = ref.read(desktopAuthProvider);
    _username.text = auth.username.isEmpty ? 'admin' : auth.username;
    _startLockout(auth.lockoutRemaining);
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startLockout(Duration remaining) {
    if (remaining.inSeconds <= 0) return;
    _lockoutTimer?.cancel();
    setState(() => _lockout = remaining.inSeconds);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _lockout--);
      if (_lockout <= 0) timer.cancel();
    });
  }

  Future<void> _submit(bool setup) async {
    final l10n = context.l10n;
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty) {
      setState(() => _error = l10n.desktopLoginUserRequired);
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = l10n.desktopLoginPasswordRequired);
      return;
    }
    if (setup) {
      if (password.length < 4) {
        setState(() => _error = l10n.desktopLoginPasswordTooShort);
        return;
      }
      if (password != _confirm.text) {
        setState(() => _error = l10n.desktopLoginPasswordMismatch);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    final notifier = ref.read(desktopAuthProvider.notifier);
    final error = setup
        ? await notifier.setUp(username: username, password: password)
        : await notifier.signIn(username: username, password: password);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _success = setup
            ? l10n.desktopLoginSetupSuccess
            : l10n.desktopLoginSuccess;
        return;
      }
      _error = error.message;
    });
    if (error != null) {
      _startLockout(ref.read(desktopAuthProvider).lockoutRemaining);
    }
  }

  Future<void> _editBackground() async {
    final l10n = context.l10n;
    final draft = await showFloatingDialog<LoginBackgroundDraft>(
      context: context,
      child: const LoginBackgroundDialog(),
    );
    if (draft == null || !mounted) return;
    final notifier = ref.read(desktopLoginBackgroundProvider.notifier);
    final error = draft.reset
        ? await notifier.reset(adminPassword: draft.adminPassword)
        : await notifier.save(
            url: draft.url,
            opacity: draft.opacity,
            blur: draft.blur,
            adminPassword: draft.adminPassword,
          );
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (draft.reset
                ? l10n.desktopLoginBackgroundResetDone
                : l10n.desktopLoginBackgroundSaved)
          : l10n.desktopLoginBackgroundFailed(error.message),
    );
  }

  void _cycleTheme() {
    final modes = AppThemeMode.values;
    final current = ref.read(themeModeProvider);
    final next = modes[(modes.indexOf(current) + 1) % modes.length];
    ref.read(themeModeProvider.notifier).select(next);
  }

  void _cyclePalette() {
    final palettes = AppPalette.values;
    final current = ref.read(paletteProvider);
    final next = palettes[(palettes.indexOf(current) + 1) % palettes.length];
    ref.read(paletteProvider.notifier).select(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = ref.watch(desktopAuthProvider);
    final background = ref.watch(desktopLoginBackgroundProvider);
    final origin = ref.watch(desktopPageOriginProvider);
    final setup = !auth.initialized;
    final colorScheme = context.colorScheme;
    final shown = background != null && background.hasImage ? background : null;
    final blur = shown == null
        ? 0.0
        : DashboardShadows.blur(shown.blur.toDouble());
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          if (shown != null) ...[
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: Image.network(
                  origin.resolve(shown.url).toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: colorScheme.scrim.withValues(
                  alpha: (shown.opacity / 100).clamp(0, 1),
                ),
              ),
            ),
          ],
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  hasBackground: shown != null,
                  onEditBackground: () => unawaited(_editBackground()),
                  onCyclePalette: _cyclePalette,
                  onCycleTheme: _cycleTheme,
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: DashboardCard(
                          semanticLabel: l10n.desktopLoginTitle,
                          child: _changing && !setup
                              ? LoginChangePasswordCard(
                                  username: _username.text.trim().isEmpty
                                      ? 'admin'
                                      : _username.text.trim(),
                                  onBack: () =>
                                      setState(() => _changing = false),
                                )
                              : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CardHeader(setup: setup),
                              const SizedBox(height: 14),
                              if (_error case final error?) ...[
                                _Notice(text: error, error: true),
                                const SizedBox(height: 10),
                              ],
                              if (_success case final success?) ...[
                                _Notice(text: success, error: false),
                                const SizedBox(height: 10),
                              ],
                              if (_lockout > 0) ...[
                                _LockoutNotice(seconds: _lockout),
                                const SizedBox(height: 10),
                              ],
                              TextField(
                                controller: _username,
                                enabled: !_busy && _lockout <= 0,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                decoration: InputDecoration(
                                  labelText: l10n.desktopLoginUserLabel,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _password,
                                enabled: !_busy && _lockout <= 0,
                                obscureText: _obscure,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => unawaited(_submit(setup)),
                                decoration: InputDecoration(
                                  labelText: setup
                                      ? l10n.desktopLoginSetupPasswordLabel
                                      : l10n.desktopLoginPasswordLabel,
                                  suffixIcon: IconButton(
                                    tooltip: _obscure
                                        ? l10n.desktopLoginShowPassword
                                        : l10n.desktopLoginHidePassword,
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: GlyphIcon(
                                      _obscure
                                          ? AppGlyphs.eyeOff
                                          : AppGlyphs.eye,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                              if (setup) ...[
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _confirm,
                                  enabled: !_busy && _lockout <= 0,
                                  obscureText: _obscure,
                                  onSubmitted: (_) =>
                                      unawaited(_submit(setup)),
                                  decoration: InputDecoration(
                                    labelText:
                                        l10n.desktopLoginConfirmLabel,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              FilledButton(
                                onPressed: _busy || _lockout > 0
                                    ? null
                                    : () => unawaited(_submit(setup)),
                                child: _busy
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CommonCircleLoading(),
                                      )
                                    : Text(
                                        setup
                                            ? l10n.desktopLoginSetupSubmit
                                            : l10n.desktopLoginSubmit,
                                      ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                spacing: 6,
                                children: [
                                  GlyphIcon(
                                    AppGlyphs.lock,
                                    size: 13,
                                    color: colorScheme.primary,
                                  ),
                                  Expanded(
                                    child: Text(
                                      l10n.desktopLoginSecurity,
                                      style: DashboardText.label(context),
                                    ),
                                  ),
                                ],
                              ),
                              if (!setup)
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton(
                                    onPressed: () =>
                                        setState(() => _changing = true),
                                    child: Text(
                                      l10n.desktopLoginChangePassword,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.desktopLoginFooter,
                    textAlign: TextAlign.center,
                    style: DashboardText.label(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.hasBackground,
    required this.onEditBackground,
    required this.onCyclePalette,
    required this.onCycleTheme,
  });

  final bool hasBackground;
  final VoidCallback onEditBackground;
  final VoidCallback onCyclePalette;
  final VoidCallback onCycleTheme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        spacing: 10,
        children: [
          Image.asset(
            dark ? 'packages/diting_shared/assets/images/icon_dark.png' : 'packages/diting_shared/assets/images/icon.png',
            width: 28,
            height: 28,
          ),
          Expanded(
            child: Text(
              l10n.desktopLoginTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.rowTitle(context),
            ),
          ),
          IconButton(
            tooltip: hasBackground
                ? l10n.desktopLoginBackgroundEnabled
                : l10n.desktopLoginBackground,
            onPressed: onEditBackground,
            icon: GlyphIcon(
              AppGlyphs.photos,
              size: 18,
              color: hasBackground
                  ? context.colorScheme.primary
                  : context.colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: l10n.desktopLoginPaletteCycle,
            onPressed: onCyclePalette,
            icon: const GlyphIcon(AppGlyphs.palette, size: 18),
          ),
          IconButton(
            tooltip: l10n.desktopLoginThemeCycle,
            onPressed: onCycleTheme,
            icon: const GlyphIcon(AppGlyphs.sun, size: 18),
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.setup});

  final bool setup;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Text(
          l10n.desktopLoginTitle,
          style: AppTextStyle.title2.of(context, emphasized: true),
        ),
        Text(
          setup
              ? l10n.desktopLoginSetupSubtitle
              : l10n.desktopLoginSubtitle,
          style: DashboardText.label(context),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          GlyphIcon(
            error ? AppGlyphs.warning : AppGlyphs.checkCircle,
            size: 16,
            color: error ? colorScheme.error : colorScheme.success,
          ),
          Expanded(
            child: Text(
              text,
              style: DashboardText.label(
                context,
                color: error ? colorScheme.error : colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockoutNotice extends StatelessWidget {
  const _LockoutNotice({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          GlyphIcon(AppGlyphs.clock, size: 16, color: colorScheme.warning),
          Expanded(
            child: Text(
              context.l10n.desktopLoginLockout(seconds),
              style: DashboardText.label(context),
            ),
          ),
        ],
      ),
    );
  }
}
