/// The protection branch's subscription lists: the rows, the counters above them, and the four
/// per-list writes.
///
/// The service is the only source of truth. Every write re-reads the list and the counters, so a
/// rejected toggle flips back on its own, and a refresh shows the health status the service recorded
/// rather than the one the page hoped for.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_filter_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopFilterListsState {
  const DesktopFilterListsState({
    this.lists = DesktopFilterLists.empty,
    this.summary = DesktopFilterSummary.empty,
    this.error,
    this.isLoading = false,
    this.saving = false,
    this.busyId,
  });

  final DesktopFilterLists lists;
  final DesktopFilterSummary summary;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  /// The list whose refresh is in flight, or [allListsBusy] for a refresh of everything.
  final String? busyId;

  bool get isStale => !isLoading && lists.total > 0 && error != null;

  bool isBusy(String id) => busyId == id;
}

/// Marks a refresh of every list; no list id can collide with it.
const String allListsBusy = '*';

class DesktopFilterListsNotifier extends Notifier<DesktopFilterListsState> {
  @override
  DesktopFilterListsState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopFilterListsState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final summary = await client.filterStats();
      final lists = await client.filterLists();
      if (ref.mounted) {
        state = DesktopFilterListsState(lists: lists, summary: summary);
      }
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopFilterListsState(
          lists: state.lists,
          summary: state.summary,
          error: error,
        );
      }
    }
  }

  /// Adds a subscription and lets the service start downloading it. Returns the failure for the
  /// page's snackbar; on success the list is re-read, so the row shows the service's own state.
  Future<DesktopApiException?> add({
    required String name,
    required String url,
  }) => _write(() async {
    await ref
        .read(desktopApiClientProvider)
        .addFilterList(name: name, url: url);
  });

  Future<DesktopApiException?> setEnabled(
    DesktopFilterList list,
    bool enabled,
  ) => _write(() async {
    await ref
        .read(desktopApiClientProvider)
        .updateFilterList(list.copyWith(enabled: enabled));
  });

  Future<DesktopApiException?> delete(String id) => _write(() async {
    await ref.read(desktopApiClientProvider).deleteFilterList(id);
  });

  Future<DesktopApiException?> refresh(String id) => _write(() async {
    state = DesktopFilterListsState(
      lists: state.lists,
      summary: state.summary,
      saving: true,
      busyId: id.isEmpty ? allListsBusy : id,
    );
    await ref.read(desktopApiClientProvider).refreshFilterLists(id);
  });

  /// Runs one write, then re-reads both answers. A failure keeps the previous rows on screen and
  /// returns the service's reason to the caller.
  Future<DesktopApiException?> _write(Future<void> Function() action) async {
    if (state.saving) return null;
    state = DesktopFilterListsState(
      lists: state.lists,
      summary: state.summary,
      saving: true,
      busyId: state.busyId,
    );
    try {
      await action();
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopFilterListsState(
          lists: state.lists,
          summary: state.summary,
          error: error,
        );
      }
      return error;
    }
    if (!ref.mounted) return null;
    state = DesktopFilterListsState(
      lists: state.lists,
      summary: state.summary,
    );
    await _load(ref.read(desktopApiClientProvider));
    return null;
  }
}

final desktopFilterListsProvider =
    NotifierProvider<DesktopFilterListsNotifier, DesktopFilterListsState>(
      DesktopFilterListsNotifier.new,
    );
