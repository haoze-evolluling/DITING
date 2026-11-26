import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class NavEntryRow extends StatelessWidget {
  const NavEntryRow({
    super.key,
    required this.glyph,
    required this.title,
    this.subtitle,
    this.onPressed,
    this.leadingSize,
    this.chevronSize = 20,
    this.enabled = true,
    this.busy = false,
    this.subtitleMaxLines,
  });

  final IconData glyph;
  final String title;
  final String? subtitle;

  final int? subtitleMaxLines;

  final VoidCallback? onPressed;

  final double? leadingSize;
  final double chevronSize;

  final bool enabled;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ListItem(
      leading: Icon(
        glyph,
        size: leadingSize,
        color: enabled ? null : colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: subtitleMaxLines,
              overflow: subtitleMaxLines == null
                  ? null
                  : TextOverflow.ellipsis,
            ),
      trailing: busy
          ? const CommonCircleLoading(size: 18)
          : Icon(
              TablerIcons.chevron_right,
              size: chevronSize,
              color: enabled ? null : colorScheme.onSurfaceVariant,
            ),
      onTap: enabled ? onPressed : null,
    );
  }
}
