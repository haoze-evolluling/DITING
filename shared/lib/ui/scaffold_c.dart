// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'scaffold.dart';

const _maxBarButtons = 3;
const _maxGroupedActions = 2;

Widget _barButton(IconButtonData data, {Widget? icon}) => ElasticPress(
  enabled: !data.isLoading && data.onPressed != null,
  child: AppBarActionButton(data: data, icon: icon),
);

/// [CommonScaffold.selectionActions] as the bar shows them, searching or not.
class _SelectionButtons {
  const _SelectionButtons(this.actions);

  final List<IconButtonData> actions;

  Iterable<IconButtonData> get _singles => actions.skip(_maxGroupedActions);

  int get slots => (actions.isEmpty ? 0 : 1) + _singles.length;

  int get buttons => actions.length;

  List<Widget> build() => [
    if (actions.isNotEmpty)
      TonalButtonGroup(
        children: [
          for (final data in actions.take(_maxGroupedActions))
            AppBarActionButton(data: data),
        ],
      ),
    for (final data in _singles) _barButton(data),
  ];
}

({List<IconButtonData> shown, List<CommonPopupMenuItem> overflow})
_foldBarActions({
  required bool hasLead,
  IconButtonData? primary,
  List<IconButtonData> icons = const [],
  IconButtonData? confirmation,
  int widgetCount = 0,
  List<CommonPopupMenuItem> menuItems = const [],
}) {
  final foldable = [?primary, ...icons];
  final fixed =
      (hasLead ? 1 : 0) + widgetCount + (confirmation == null ? 0 : 1);
  if (fixed + foldable.length + (menuItems.isEmpty ? 0 : 1) <= _maxBarButtons) {
    return (shown: [...foldable, ?confirmation], overflow: menuItems);
  }
  final slots = _maxBarButtons - 1 - fixed;
  final kept = foldable.take(slots < 0 ? 0 : slots).toList();
  bool isKept(IconButtonData data) => kept.any((it) => identical(it, data));
  return (
    shown: [
      for (final data in foldable)
        if (isKept(data)) data,
      ?confirmation,
    ],
    overflow: [
      for (final data in foldable)
        if (!isKept(data))
          CommonPopupMenuItem(
            glyph: data.glyph,
            label: data.tooltip ?? '',
            checked: data.isSelected,
            onPressed: data.isLoading ? null : data.onPressed,
          ),
      ...menuItems,
    ],
  );
}

class _OverflowMenuButton extends StatelessWidget {
  const _OverflowMenuButton({required this.items});

  final List<CommonPopupMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return CommonPopupBox(
      targetBuilder: (open) => IconButton(
        tooltip: UiLocalizations.of(context).more,
        onPressed: open,
        icon: const GlyphIcon(AppGlyphs.more),
      ),
      popupBuilder: (_) => CommonPopupMenu(items: items),
    );
  }
}

/// An app bar action from [IconButtonData], standing in a spinner while the
/// action runs.
class AppBarActionButton extends StatelessWidget {
  const AppBarActionButton({super.key, required this.data, this.icon});

  final IconButtonData data;

  /// Stands in for the glyph of [data].
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return IconButton(
      tooltip: data.tooltip,
      isSelected: data.isSelected,
      style: data.isSelected == true
          ? IconButton.styleFrom(
              backgroundColor: TonalButtonTheme.glassOf(context)
                  ? null
                  : colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            )
          : null,
      onPressed: data.isLoading ? null : data.onPressed,
      icon: data.isLoading
          ? CommonCircleLoading(size: TonalButtonSize.bar.icon)
          : icon ?? GlyphIcon(data.glyph),
    );
  }
}

/// What the surface a scaffold sits on asks of its chrome.
///
/// A sheet page is a pushed route and wears a page's chrome. A bottom sheet
/// floats its bar over the body; it and a phone page pushed over the one with
/// the tab bar search from a field docked over their foot instead of a button
/// that takes the bar over.
class _SheetForm {
  const _SheetForm({
    required this.isCompact,
    required this.hasDragHandle,
    required this.dockedSearch,
    required this.pop,
  });

  factory _SheetForm.of(
    BuildContext context, {
    required AppBarSearchState? searchState,
    required bool searchInBar,
    required bool hasConfirmationAction,
  }) {
    final provider = SheetProvider.of(context);
    final isModal = provider != null && provider.type != SheetType.page;
    final isCompact = provider?.type.isCompact ?? false;
    // iOS 27 docks the search of a phone page with no tab bar under it at its
    // foot, a glass field in sight at rest.
    final docksSearch =
        isCompact ||
        (!searchInBar &&
            !isModal &&
            ViewScope.isMobileOf(context) &&
            ModalRoute.of(context)?.impliesAppBarDismissal == true);
    return _SheetForm(
      isCompact: isCompact,
      hasDragHandle: provider?.type == SheetType.bottomSheet,
      dockedSearch: docksSearch ? searchState : null,
      pop: !isModal
          ? null
          : _SheetPop.of(
              context,
              provider,
              hasConfirmationAction:
                  hasConfirmationAction && searchState == null,
            ),
    );
  }

  final bool isCompact;
  final bool hasDragHandle;
  final AppBarSearchState? dockedSearch;
  final _SheetPop? pop;

  bool get hasDockedSearch => dockedSearch != null;
}

/// How a sheet's own pop button reads: [useCloseIcon] where it dismisses the
/// sheet. It leads the bar wherever it is, as SwiftUI places a close in
/// `.cancellationAction`, unless [atFoot] turns it into a form's cancel.
class _SheetPop {
  const _SheetPop({required this.useCloseIcon, required this.atFoot});

  factory _SheetPop.of(
    BuildContext context,
    SheetProvider provider, {
    required bool hasConfirmationAction,
  }) {
    final useCloseIcon =
        provider.nestedNavigatorPop == null ||
        ModalRoute.of(context)?.impliesAppBarDismissal == false;
    final atFoot =
        useCloseIcon &&
        hasConfirmationAction &&
        provider.type == SheetType.formSheet;
    return _SheetPop(useCloseIcon: useCloseIcon, atFoot: atFoot);
  }

  final bool useCloseIcon;
  final bool atFoot;
}

const double appBarActionSpace = 4;

const double _barButtonGap = 8;
const double _headerOverhang = 16;
const double _iconButtonTapPadding = 4;

/// Where a filled button sits from the app bar edge, leading included: the
/// layout margin iOS gives a compact and a regular width.
double appBarActionInset(bool compact) => compact ? 16 : 20;

double _iconActionInset(bool isMobileView) => isMobileView ? 4 : 8;

double appBarLeadingWidth(bool compact) =>
    TonalButtonSize.bar.button + appBarActionInset(compact) * 2;

/// A phone view or a sheet: an iOS compact width.
bool _isCompactBar(BuildContext context, bool isMobileView) {
  final sheet = SheetProvider.of(context)?.type;
  return isMobileView || (sheet != null && sheet != SheetType.page);
}

enum AppBarActionEdge {
  icon,
  container;

  double spaceOf(BuildContext context, bool isMobileView) => switch (this) {
    icon => _iconActionInset(isMobileView) - _tapPaddingOf(context),
    container => appBarActionInset(_isCompactBar(context, isMobileView)),
  };

  double get gap => switch (this) {
    icon => appBarActionSpace,
    container => _barButtonGap,
  };
}

/// Only the touch platforms ask for the 48 dp target that pads the container out.
double _tapPaddingOf(BuildContext context) =>
    Theme.of(context).materialTapTargetSize == MaterialTapTargetSize.padded
    ? _iconButtonTapPadding
    : 0;

List<Widget> genActions(
  List<Widget> actions, {
  required AppBarActionEdge edge,
}) {
  return <Widget>[
    ...actions.separated(SizedBox(width: edge.gap)),
    _ActionEdgeGap(edge),
  ];
}

class _ActionEdgeGap extends StatelessWidget {
  const _ActionEdgeGap(this.edge);

  final AppBarActionEdge edge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: edge.spaceOf(context, ViewScope.isMobileOf(context)),
    );
  }
}

class AppBarInsetScope extends StatelessWidget {
  const AppBarInsetScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = _isCompactBar(context, ViewScope.isMobileOf(context));
    return Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          leadingWidth: appBarLeadingWidth(compact),
          toolbarHeight: pageToolbarHeight,
        ),
      ),
      child: child,
    );
  }
}

/// A route over the home page on the root navigator fills the window, with
/// neither the window header nor the sidebar keeping it off the buttons.
class _TitleMenuButton extends StatelessWidget {
  const _TitleMenuButton({
    required this.title,
    required this.compact,
    required this.onPressed,
  });

  final String title;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // No ink: the padding it needs would move the title off its place in the
    // bar, and a press turns the title into its menu at once.
    return InkWell(
      onTap: onPressed,
      customBorder: AppShape.sm,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: compact ? 2 : 4,
        children: [
          Flexible(child: Text(title)),
          GlyphIcon(
            AppGlyphs.chevronDown,
            size: compact ? 16 : 20,
            color: context.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _WindowControlsClearance extends StatelessWidget {
  const _WindowControlsClearance({required this.child});

  final Widget child;

  static bool _fillsWindow(BuildContext context) {
    final route = ModalRoute.of(context);
    return route != null &&
        route.opaque &&
        !route.isFirst &&
        route.navigator == Navigator.maybeOf(context, rootNavigator: true);
  }

  @override
  Widget build(BuildContext context) {
    final controls = ViewScope.windowControlsOf(context);
    if (controls.isEmpty || !_fillsWindow(context)) {
      return child;
    }
    final mediaQuery = MediaQuery.of(context);
    final padding = mediaQuery.padding;
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: padding.copyWith(left: math.max(padding.left, controls.width)),
      ),
      child: child,
    );
  }
}

class BaseScaffold extends StatelessWidget {
  final String title;
  final Widget body;

  const BaseScaffold({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(body: body, title: title);
  }
}
