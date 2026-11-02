/// Client groups: the whole configuration is read and written at once, so the page owns the draft
/// and the notifier only performs the save and re-read.
///
/// `/clients/groups` answers a POST with a success flag, so the save re-reads the configuration; the
/// service may drop invalid members or schedules, and the page then shows what was actually stored.
library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_client_groups_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopClientGroupsState {
  const DesktopClientGroupsState({
    this.data,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopClientGroups? data;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => data != null && error != null;
}

class DesktopClientGroupsNotifier
    extends Notifier<DesktopClientGroupsState> {
  @override
  DesktopClientGroupsState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopClientGroupsState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final data = await client.clientGroups();
      if (ref.mounted) state = DesktopClientGroupsState(data: data);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopClientGroupsState(data: state.data, error: error);
      }
    }
  }

  Future<DesktopApiException?> save({
    required bool enabled,
    required List<DesktopClientGroup> groups,
  }) async {
    if (state.saving) return null;
    state = DesktopClientGroupsState(data: state.data, saving: true);
    try {
      await ref
          .read(desktopApiClientProvider)
          .configureClientGroups(enabled: enabled, groups: groups);
      await _load(ref.read(desktopApiClientProvider));
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopClientGroupsState(data: state.data, error: error);
      }
      return error;
    }
  }
}

final desktopClientGroupsProvider =
    NotifierProvider<DesktopClientGroupsNotifier, DesktopClientGroupsState>(
      DesktopClientGroupsNotifier.new,
    );
