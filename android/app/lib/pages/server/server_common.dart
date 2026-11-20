import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/data/vpn/power_state.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

PowerState serverPowerState(ServerStatus status) {
  if (status.running) return PowerState.running;
  if (status.starting) return PowerState.starting;
  if (status.error != null) return PowerState.error;
  return PowerState.stopped;
}

String serverCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 10000) return '${(value / 1000).toStringAsFixed(1)}K';
  return '$value';
}

String serverPercent(double value) =>
    '${(value * 100).clamp(0, 100).toStringAsFixed(1)}%';

String serverMs(double value) =>
    '${value.toStringAsFixed(value < 10 ? 1 : 0)} ms';

class ServerErrorCard extends StatelessWidget {
  const ServerErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: CommonCard(
        isError: true,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            const GlyphIcon(AppGlyphs.error, size: 20),
            Expanded(
              child: Text(
                message,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: scheme.onErrorContainer),
              ),
            ),
            if (onRetry != null)
              if (retryLabel case final label?)
                TextButton(onPressed: onRetry, child: Text(label))
              else
                IconButton(
                  tooltip: context.l10n.serverRetry,
                  onPressed: onRetry,
                  icon: const GlyphIcon(AppGlyphs.refresh, size: 18),
                ),
          ],
        ),
      ),
    );
  }
}

class ServerSectionCard extends StatelessWidget {
  const ServerSectionCard({
    super.key,
    required this.child,
    this.onPressed,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: AppShape.standard,
          shadows: DashboardShadows.e1(context),
        ),
        child: CommonCard(onPressed: onPressed, padding: padding, child: child),
      ),
    );
  }
}

/// One choice in a [ServerOptionRow].
class ServerOption<T> {
  const ServerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.glyph,
  });

  final T value;
  final String label;
  final String? subtitle;
  final Glyph? glyph;
}

/// A settings row whose value opens the product popup menu.
class ServerOptionRow<T> extends StatelessWidget {
  const ServerOptionRow({
    super.key,
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    this.glyph,
  }) : assert(options.length > 0);

  final String title;
  final List<ServerOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Glyph? glyph;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
    PopupOpen? openMenu;
    return ListItem(
      leading: GlyphIcon(
        glyph ?? selected.glyph ?? AppGlyphs.sliders,
        size: 20,
      ),
      title: Text(title),
      subtitle: selected.subtitle == null ? null : Text(selected.subtitle!),
      onTap: () => openMenu?.call(),
      trailing: CommonPopupBox(
        targetBuilder: (open) {
          openMenu = open;
          return _OptionValue(label: selected.label, onPressed: open);
        },
        popupBuilder: (_) => CommonPopupMenu(
          items: [
            for (final option in options)
              CommonPopupMenuItem(
                label: option.label,
                subtitle: option.subtitle,
                glyph: option.glyph,
                checked: option.value == value,
                onPressed: () => onChanged(option.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionValue extends StatelessWidget {
  const _OptionValue({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: context.colorScheme.onSurfaceVariant,
        textStyle: context.listTitleStyle,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          const GlyphIcon(AppGlyphs.picker, size: 16),
        ],
      ),
    );
  }
}

Future<int?> editServerNumber(
  BuildContext context, {
  required String title,
  required int initial,
  int min = 1,
  int max = 86400,
  String? suffix,
}) {
  return showFloatingDialog<int>(
    context: context,
    child: _ServerNumberDialog(
      title: title,
      initial: initial,
      min: min,
      max: max,
      suffix: suffix,
    ),
  );
}

Future<String?> editServerText(
  BuildContext context, {
  required String title,
  required String initial,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showFloatingDialog<String>(
    context: context,
    child: CommonDialog(
      title: title,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(context.l10n.commonSave),
        ),
      ],
      child: TextField(controller: controller, autofocus: true),
    ),
  );
  controller.dispose();
  return value == null || value.isEmpty ? null : value;
}

class _ServerNumberDialog extends StatefulWidget {
  const _ServerNumberDialog({
    required this.title,
    required this.initial,
    required this.min,
    required this.max,
    this.suffix,
  });

  final String title;
  final int initial;
  final int min;
  final int max;
  final String? suffix;

  @override
  State<_ServerNumberDialog> createState() => _ServerNumberDialogState();
}

class _ServerNumberDialogState extends State<_ServerNumberDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.initial}',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < widget.min || value > widget.max) {
      setState(() => _error = context.l10n.serverNumberInvalid);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: widget.title,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(onPressed: _submit, child: Text(context.l10n.commonSave)),
      ],
      child: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.title,
          suffixText: widget.suffix,
          errorText: _error,
        ),
      ),
    );
  }
}
