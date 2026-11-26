import 'package:diting_android/ui/icons/brand_glyph.dart';
import 'package:material_ui/material_ui.dart';

/// An icon on a site-latency target: either a Tabler glyph or one of the few
/// brand marks that Tabler does not ship.
sealed class SiteIcon {
  const SiteIcon();
}

final class TablerSiteIcon extends SiteIcon {
  const TablerSiteIcon(this.icon);

  final IconData icon;
}

final class BrandSiteIcon extends SiteIcon {
  const BrandSiteIcon(this.glyph);

  final BrandGlyph glyph;
}

class SiteIconView extends StatelessWidget {
  const SiteIconView(this.icon, {super.key, this.size, this.color});

  final SiteIcon icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) => switch (icon) {
    TablerSiteIcon(:final icon) => Icon(icon, size: size, color: color),
    BrandSiteIcon(:final glyph) => BrandGlyphIcon(
      glyph,
      size: size,
      color: color,
    ),
  };
}
