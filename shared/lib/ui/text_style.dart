// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:material_ui/material_ui.dart';

import 'font.dart';

extension TextStyleExtension on TextStyle {
  TextStyle get toTabular => copyWith(fontFeatures: appTabularFigures);
}
