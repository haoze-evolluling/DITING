// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:material_ui/material_ui.dart';

import 'color.dart';
import 'font.dart';

extension TextStyleExtension on TextStyle {
  TextStyle get toLight => copyWith(color: color?.opacity80);

  TextStyle get toLighter => copyWith(color: color?.opacity60);

  /// Lining figures in the current family; the app never overrides the family itself, so an
  /// imported font stays in effect for numbers too.
  TextStyle get toTabular => copyWith(fontFeatures: appTabularFigures);
}
