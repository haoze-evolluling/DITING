import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:material_ui/material_ui.dart';

/// Scroll body for the app pickers: same app-bar inset and dock clearance as [PageBody], but built
/// from slivers so the app section can stay lazy.
///
/// Thin alias of [SliverPageBody], kept because the app-picker call sites predate it.
class AppListScrollView extends StatelessWidget {
  const AppListScrollView({super.key, required this.slivers});

  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => SliverPageBody(slivers: slivers);
}

/// Lazily built app rows for a [CustomScrollView].
///
/// Alias of [lazySectionSlivers] with the app-picker defaults, kept for the existing call sites.
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

/// The 1.4.3 `AppListOverflowMenu` in Flutter form: select-all / clear / invert, then the filter and
/// sort submenus. Callers pass the actions they support; a null callback drops that entry, which is
/// how the legacy `showSelectionActions` flag behaves.
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
        glyph: AppGlyphs.checkDouble,
        onPressed: onSelectAll,
      ),
    if (onClear != null)
      CommonPopupMenuItem(
        label: l10n.commonClear,
        glyph: AppGlyphs.clearAll,
        onPressed: onClear,
      ),
    if (onInvert != null)
      CommonPopupMenuItem(
        label: l10n.commonInvertSelection,
        glyph: AppGlyphs.sync,
        onPressed: onInvert,
      ),
    CommonPopupMenuItem(
      label: l10n.commonFilter,
      glyph: AppGlyphs.filter,
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
      glyph: AppGlyphs.sort,
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
