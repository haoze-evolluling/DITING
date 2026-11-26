import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:material_ui/material_ui.dart';

class AppListScrollView extends StatelessWidget {
  const AppListScrollView({super.key, required this.slivers});

  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => SliverPageBody(slivers: slivers);
}

List<Widget> appListSlivers({
  String? title,
  List<IconButtonData> actions = const [],
  required int itemCount,
  required NullableIndexedWidgetBuilder itemBuilder,
  String? footer,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16),
}) {
  return lazySectionSlivers(
    title: title,
    actions: actions,
    itemCount: itemCount,
    itemBuilder: itemBuilder,
    footer: footer,
    padding: padding,
  );
}

List<CommonPopupMenuItem> appListMenuItems({
  required AppL10n l10n,
  required AppListFilter filter,
  required AppListSort sort,
  required ValueChanged<AppListFilter> onFilterChanged,
  required ValueChanged<AppListSort> onSortChanged,
  VoidCallback? onSelectAll,
  VoidCallback? onClear,
  VoidCallback? onInvert,
}) {
  return [
    if (onSelectAll != null)
      CommonPopupMenuItem(
        label: l10n.commonSelectAll,
        glyph: TablerIcons.checks,
        onPressed: onSelectAll,
      ),
    if (onClear != null)
      CommonPopupMenuItem(
        label: l10n.commonClear,
        glyph: TablerIcons.trash,
        onPressed: onClear,
      ),
    if (onInvert != null)
      CommonPopupMenuItem(
        label: l10n.commonInvertSelection,
        glyph: TablerIcons.rotate_clockwise,
        onPressed: onInvert,
      ),
    CommonPopupMenuItem(
      label: l10n.commonFilter,
      glyph: TablerIcons.filter,
      subItems: [
        for (final option in AppListFilter.values)
          CommonPopupMenuItem(
            label: option.label(l10n),
            checked: option == filter,
            onPressed: () => onFilterChanged(option),
          ),
      ],
    ),
    CommonPopupMenuItem(
      label: l10n.commonSort,
      glyph: TablerIcons.sort_ascending,
      subItems: [
        for (final option in AppListSort.values)
          CommonPopupMenuItem(
            label: option.label(l10n),
            checked: option == sort,
            onPressed: () => onSortChanged(option),
          ),
      ],
    ),
  ];
}
