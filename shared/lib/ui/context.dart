// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/inherited.dart';
import 'package:diting_shared/ui/metrics.dart';
import 'package:diting_shared/ui/view_scope.dart';
import 'package:material_ui/material_ui.dart';

extension BuildContextExtension on BuildContext {
  bool get isMobileView => ViewScope.isMobileOf(this, listen: false);

  void safeNestedPop<T extends Object?>([T? result]) {
    final nestedPop = SheetProvider.of(this)?.nestedNavigatorPop;
    if (nestedPop != null) {
      return nestedPop(result);
    } else {
      return Navigator.of(this).pop(result);
    }
  }

  bool get isInCompactSheet => SheetProvider.of(this)?.type.isCompact ?? false;

  double get appBarInset =>
      FloatingBarScope.of(this) ??
      (isInCompactSheet
          ? sheetAppBarHeight
          : MediaQuery.paddingOf(this).top + pageToolbarHeight);

  double get contentTopPadding =>
      TopInsetScope.of(this) ??
      (isInCompactSheet ? sheetAppBarHeight : appBarInset + 12);

  double get bottomInset =>
      BottomInsetScope.of(this) + MediaQuery.paddingOf(this).bottom;

  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  bool get disableAnimations => MediaQuery.disableAnimationsOf(this);

  Duration motionDuration(Duration duration) =>
      disableAnimations ? Duration.zero : duration;
}
