library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Immediate feedback for a config change: these switches apply at once, so a rejection
/// would otherwise show only as the switch bouncing back.
void showConfigHint(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1600),
    ),
  );
}

Future<bool> confirmConfigAction(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
}) async {
  final confirmed = await showFloatingDialog<bool>(
    context: context,
    child: CommonDialog(
      title: title,
      destructive: true,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context, false),
          child: Text(context.l10n.configCancel),
        ),
        TextButton(
          onPressed: () => popFloatingDialog(context, true),
          child: Text(confirmLabel ?? context.l10n.configDelete),
        ),
      ],
      child: Text(message),
    ),
  );
  return confirmed ?? false;
}

/// Not `ListItem.input`, which opens a dialog on tap.
class ConfigFieldRow extends StatelessWidget {
  const ConfigFieldRow({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;

  /// Note below the field, better than a placeholder for explaining the value.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 12,
            children: [
              SizedBox(
                width: 76,
                child: Text(label, style: context.listTitleStyle),
              ),
              Expanded(child: child),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 88),
              child: Text(hint, style: context.listCaptionStyle),
            ),
        ],
      ),
    );
  }
}

/// Trailing remove button, wrapped in `CommonMinIconButtonTheme`: a default IconButton tap
/// target would stretch the row height.
class ConfigRemoveButton extends StatelessWidget {
  const ConfigRemoveButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.glyph = AppGlyphs.removeCircle,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    return CommonMinIconButtonTheme(
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: GlyphIcon(
          glyph,
          size: 18,
          color: onPressed == null
              ? context.colorScheme.onSurface.withValues(alpha: 0.3)
              : context.colorScheme.error,
        ),
      ),
    );
  }
}

/// Subtitle for list entries: report the count, and explain an empty list.
String configListSummary(
  List<String> items, {
  String? empty,
  AppL10n? l10n,
}) {
  final text = l10n ?? currentL10n;
  return items.isEmpty
      ? (empty ?? text.configNotSet)
      : text.configItemCount(items.length);
}
