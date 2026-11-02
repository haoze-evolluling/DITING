// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Hand-written stand-ins for the upstream's freezed models; `copyWith` keeps freezed's rules.
const _keep = Object();

@immutable
class IconButtonData {
  const IconButtonData({
    required this.glyph,
    required this.onPressed,
    this.tooltip,
    this.isLoading = false,
    this.isSelected,
  });

  final Glyph glyph;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isLoading;

  final bool? isSelected;

  IconButtonData copyWith({
    Glyph? glyph,
    Object? onPressed = _keep,
    Object? tooltip = _keep,
    bool? isLoading,
    Object? isSelected = _keep,
  }) {
    return IconButtonData(
      glyph: glyph ?? this.glyph,
      onPressed: onPressed == _keep
          ? this.onPressed
          : onPressed as VoidCallback?,
      tooltip: tooltip == _keep ? this.tooltip : tooltip as String?,
      isLoading: isLoading ?? this.isLoading,
      isSelected: isSelected == _keep ? this.isSelected : isSelected as bool?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IconButtonData &&
          other.glyph == glyph &&
          other.onPressed == onPressed &&
          other.tooltip == tooltip &&
          other.isLoading == isLoading &&
          other.isSelected == isSelected;

  @override
  int get hashCode =>
      Object.hash(glyph, onPressed, tooltip, isLoading, isSelected);
}

@immutable
class AppBarState {
  const AppBarState({this.searchState});

  final AppBarSearchState? searchState;

  AppBarState copyWith({Object? searchState = _keep}) {
    return AppBarState(
      searchState: searchState == _keep
          ? this.searchState
          : searchState as AppBarSearchState?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBarState && other.searchState == searchState;

  @override
  int get hashCode => Object.hash(AppBarState, searchState);
}

@immutable
class AppBarSearchState {
  const AppBarSearchState({required this.onSearch, this.query});

  final Function(String) onSearch;
  final String? query;

  AppBarSearchState copyWith({
    Function(String)? onSearch,
    Object? query = _keep,
  }) {
    return AppBarSearchState(
      onSearch: onSearch ?? this.onSearch,
      query: query == _keep ? this.query : query as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBarSearchState &&
          other.onSearch == onSearch &&
          other.query == query;

  @override
  int get hashCode => Object.hash(onSearch, query);
}
