/// The service catalogue's selection and per-service plans.
///
/// `/filter/services` answers with the whole state after every write, so the page adopts that answer
/// directly instead of re-reading; a rejected write keeps the previous state and returns the reason.
library;

import 'dart:async';

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_schedule_models.dart';
import 'package:diting/desktop/data/api/desktop_services_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopServicesState {
  const DesktopServicesState({
    this.data,
    this.error,
    this.isLoading = false,
    this.saving = false,
  });

  final DesktopBlockedServices? data;
  final DesktopApiException? error;
  final bool isLoading;
  final bool saving;

  bool get isStale => data != null && error != null;
}

class DesktopServicesNotifier extends Notifier<DesktopServicesState> {
  @override
  DesktopServicesState build() {
    unawaited(_load(ref.read(desktopApiClientProvider)));
    return const DesktopServicesState(isLoading: true);
  }

  Future<void> reload() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final data = await client.blockedServices();
      if (ref.mounted) state = DesktopServicesState(data: data);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopServicesState(data: state.data, error: error);
      }
    }
  }

  Future<DesktopApiException?> toggleService(String id, bool blocked) {
    final data = state.data;
    if (data == null) return Future.value(null);
    final ids = {...data.blockedIds};
    if (blocked) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    return _write({'ids': ids.toList(), 'groups': data.blockedGroups.toList()});
  }

  /// Blocking a whole group drops that group's individually blocked services, exactly like the
  /// console: keeping them would make them stay blocked after the group is switched off.
  Future<DesktopApiException?> toggleGroup(DesktopServiceGroup group) {
    final data = state.data;
    if (data == null) return Future.value(null);
    final groups = {...data.blockedGroups};
    var ids = {...data.blockedIds};
    if (groups.remove(group.id)) {
      // Unblocking the group leaves the individual choices as they were.
    } else {
      groups.add(group.id);
      final inGroup = {
        for (final service in data.services)
          if (service.group == group.id) service.id,
      };
      ids = ids.difference(inGroup);
    }
    return _write({'ids': ids.toList(), 'groups': groups.toList()});
  }

  Future<DesktopApiException?> clearAll() =>
      _write({'ids': const <String>[], 'groups': const <String>[]});

  /// Saves one service's weekly plan; an empty list removes the plan (back to always blocking).
  Future<DesktopApiException?> saveSchedules(
    String serviceId,
    List<DesktopSchedule> schedules,
  ) {
    final data = state.data;
    if (data == null) return Future.value(null);
    final next = <String, Object?>{
      for (final entry in data.schedules.entries)
        entry.key: [for (final row in entry.value) row.toJson()],
    };
    if (schedules.isEmpty) {
      next.remove(serviceId);
    } else {
      next[serviceId] = [for (final row in schedules) row.toJson()];
    }
    return _write({'schedules': next});
  }

  Future<DesktopApiException?> _write(Map<String, Object?> body) async {
    if (state.saving) return null;
    state = DesktopServicesState(data: state.data, saving: true);
    try {
      final data = await ref
          .read(desktopApiClientProvider)
          .configureBlockedServices(body);
      if (ref.mounted) state = DesktopServicesState(data: data);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopServicesState(data: state.data, error: error);
      }
      return error;
    }
  }
}

final desktopServicesProvider =
    NotifierProvider<DesktopServicesNotifier, DesktopServicesState>(
      DesktopServicesNotifier.new,
    );
