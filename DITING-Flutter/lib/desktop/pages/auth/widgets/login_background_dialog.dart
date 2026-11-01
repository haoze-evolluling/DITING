/// The login page's background editor: a stored image or an external URL, plus the dark overlay and
/// blur the login page applies.
///
/// The old desktop console's `auth/LoginBgModal.vue` is the blueprint. It only collects the draft;
/// the page performs the write and reports the service's answer, so a rejected save never looks like
/// a saved one. No client-side resizing: the service caps the payload and validates the header.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_auth_providers.dart';
import 'package:diting/desktop/data/host/desktop_platform_host.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// What the dialog collected. [reset] means "restore the default wallpaper" and ignores the rest.
class LoginBackgroundDraft {
  const LoginBackgroundDraft({
    this.url = '',
    this.opacity = 40,
    this.blur = 0,
    this.adminPassword = '',
    this.reset = false,
  });

  final String url;
  final int opacity;
  final int blur;
  final String adminPassword;
  final bool reset;
}

class LoginBackgroundDialog extends ConsumerStatefulWidget {
  const LoginBackgroundDialog({super.key});

  @override
  ConsumerState<LoginBackgroundDialog> createState() =>
      _LoginBackgroundDialogState();
}

class _LoginBackgroundDialogState
    extends ConsumerState<LoginBackgroundDialog> {
  final _url = TextEditingController();
  final _password = TextEditingController();
  bool _local = true;
  String _dataUrl = '';
  double _opacity = 40;
  double _blur = 0;
  String? _error;
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    final background = ref.read(desktopLoginBackgroundProvider);
    _opacity = (background?.opacity ?? 40).toDouble();
    _blur = (background?.blur ?? 0).toDouble();
    if (background != null && background.type == 'url') {
      _local = false;
      _url.text = background.url;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _password.dispose();
    super.dispose();
  }

  /// The service only asks a remote, unauthenticated browser for the admin password; loopback and
  /// an existing session are already trusted.
  bool get _needsPassword {
    final auth = ref.read(desktopAuthProvider);
    if (auth.signedIn || !auth.initialized) return false;
    final host = ref.read(desktopPageOriginProvider).host;
    return !(host.isEmpty ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1');
  }

  String get _effectiveUrl => _local ? _dataUrl : _url.text.trim();

  Future<void> _pickImage() async {
    final picked = await pickDesktopImageDataUrl();
    if (!mounted) return;
    if (picked == null) {
      setState(() => _error = context.l10n.desktopLoginBackgroundNoFile);
      return;
    }
    setState(() {
      _error = null;
      _preparing = true;
      _local = true;
    });
    // Shrunk before it is stored: the service caps the payload, but a phone photo is wasteful.
    final prepared = await compressDesktopImageDataUrl(picked);
    if (!mounted) return;
    setState(() {
      _preparing = false;
      _dataUrl = prepared ?? picked;
    });
  }

  void _save() {
    final l10n = context.l10n;
    final url = _effectiveUrl;
    if (url.isEmpty) {
      setState(() => _error = l10n.desktopLoginBackgroundNeedImage);
      return;
    }
    if (!_local &&
        !url.startsWith('http://') &&
        !url.startsWith('https://')) {
      setState(() => _error = l10n.desktopLoginBackgroundUrlInvalid);
      return;
    }
    popFloatingDialog(
      context,
      LoginBackgroundDraft(
        url: url,
        opacity: _opacity.round(),
        blur: _blur.round(),
        adminPassword: _needsPassword ? _password.text : '',
      ),
    );
  }

  void _reset() {
    popFloatingDialog(
      context,
      LoginBackgroundDraft(
        adminPassword: _needsPassword ? _password.text : '',
        reset: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: l10n.desktopLoginBackgroundTitle,
      hasFields: true,
      width: 480,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: _reset,
          child: Text(l10n.desktopLoginBackgroundReset),
        ),
        TextButton(
          onPressed: _save,
          child: Text(l10n.desktopLoginBackgroundSave),
        ),
      ],
      child: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              _Preview(
                dataUrl: _local ? _dataUrl : '',
                url: _local ? '' : _url.text.trim(),
                opacity: _opacity.round(),
                blur: _blur.round(),
              ),
              Wrap(
                spacing: 8,
                children: [
                  _SourceButton(
                    label: l10n.desktopLoginBackgroundLocal,
                    selected: _local,
                    onPressed: () => setState(() => _local = true),
                  ),
                  _SourceButton(
                    label: l10n.desktopLoginBackgroundUrl,
                    selected: !_local,
                    onPressed: () => setState(() => _local = false),
                  ),
                ],
              ),
              if (_local)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: _preparing ? null : _pickImage,
                    icon: _preparing
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CommonCircleLoading(),
                          )
                        : const GlyphIcon(AppGlyphs.photos, size: 16),
                    label: Text(
                      _preparing
                          ? l10n.desktopLoginBackgroundPreparing
                          : l10n.desktopLoginBackgroundChoose,
                    ),
                  ),
                )
              else
                TextField(
                  controller: _url,
                  decoration: InputDecoration(
                    labelText: l10n.desktopLoginBackgroundUrlLabel,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              _Slider(
                label: l10n.desktopLoginBackgroundOpacity,
                value: _opacity,
                max: 100,
                onChanged: (value) => setState(() => _opacity = value),
              ),
              _Slider(
                label: l10n.desktopLoginBackgroundBlur,
                value: _blur,
                max: 20,
                onChanged: (value) => setState(() => _blur = value),
              ),
              if (_needsPassword) ...[
                Text(
                  l10n.desktopLoginBackgroundPasswordBody,
                  style: DashboardText.label(context),
                ),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.desktopLoginBackgroundPassword,
                  ),
                ),
              ],
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
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return FilledButton.tonal(onPressed: onPressed, child: Text(label));
    }
    return OutlinedButton(onPressed: onPressed, child: Text(label));
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: DashboardText.label(context)),
            ),
            Text('${value.round()}', style: DashboardText.label(context)),
          ],
        ),
        Slider(
          value: value,
          max: max,
          divisions: max.round(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.dataUrl,
    required this.url,
    required this.opacity,
    required this.blur,
  });

  final String dataUrl;
  final String url;
  final int opacity;
  final int blur;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final bytes = _decodeDataUrl(dataUrl);
    final image = bytes != null
        ? Image.memory(bytes, fit: BoxFit.cover)
        : url.isEmpty
        ? null
        : Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
    return ClipRRect(
      borderRadius: AppRadius.md,
      child: SizedBox(
        height: 140,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: SurfaceLevel.block.colorOf(colorScheme)),
            if (image != null)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: DashboardShadows.blur(blur.toDouble()),
                  sigmaY: DashboardShadows.blur(blur.toDouble()),
                ),
                child: image,
              ),
            if (image != null)
              ColoredBox(
                color: colorScheme.scrim.withValues(
                  alpha: (opacity / 100).clamp(0, 1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Decodes a `data:image/...;base64,` payload for the preview; null for anything else.
Uint8List? _decodeDataUrl(String value) {
  if (!value.startsWith('data:image/')) return null;
  final comma = value.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(value.substring(comma + 1));
  } on FormatException {
    return null;
  }
}
