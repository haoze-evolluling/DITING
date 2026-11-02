import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// A list row that opens something: leading glyph, title, one-line subtitle, trailing chevron.
///
/// Four page-local copies of this row (`_Entry`, `_SettingsRow`, `_MenuRow`, `ConfigEntryRow`) and
/// about twenty inline `ListItem`s differed only in the chevron metric and whether the row greys out
/// when unavailable, so both are parameters here rather than separate widgets.
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
  });

  final Glyph glyph;
  final String title;
  final String? subtitle;

  /// `null` renders a row that cannot be tapped, e.g. one gated on a granted permission.
  final VoidCallback? onPressed;

  /// `null` keeps the `GlyphIcon` default, which is what the larger rows use.
  final double? leadingSize;
  final double chevronSize;

  /// Greys the leading glyph and blocks taps; the row stays legible as a destination.
  final bool enabled;

  /// Swaps the chevron for a spinner while the row's action is already running.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ListItem(
      leading: GlyphIcon(
        glyph,
        size: leadingSize,
        color: enabled ? null : colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: busy
          ? const CommonCircleLoading(size: 18)
          : GlyphIcon(
              AppGlyphs.chevronForward,
              size: chevronSize,
              color: enabled ? null : colorScheme.onSurfaceVariant,
            ),
      onTap: enabled ? onPressed : null,
    );
  }
}
