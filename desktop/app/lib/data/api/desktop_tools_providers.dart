library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_tools_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DesktopPortCheckState {
  const DesktopPortCheckState({
    this.result,
    this.error,
    this.checking = false,
    this.fixing = false,
  });

  final DesktopPortCheck? result;
  final DesktopApiException? error;
  final bool checking;
  final bool fixing;

  bool get busy => checking || fixing;
}

class DesktopPortCheckNotifier extends Notifier<DesktopPortCheckState> {
  @override
  DesktopPortCheckState build() => const DesktopPortCheckState();

  Future<void> check() async {
    if (state.busy) return;
    state = DesktopPortCheckState(result: state.result, checking: true);
    try {
      final result = await ref.read(desktopApiClientProvider).portCheck();
      if (ref.mounted) state = DesktopPortCheckState(result: result);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopPortCheckState(result: state.result, error: error);
      }
    }
  }

  Future<DesktopApiException?> autofix() async {
    if (state.busy) return null;
    state = DesktopPortCheckState(result: state.result, fixing: true);
    try {
      final result = await ref
          .read(desktopApiClientProvider)
          .autofixPort();
      if (ref.mounted) state = DesktopPortCheckState(result: result);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopPortCheckState(result: state.result, error: error);
      }
      return error;
    }
  }
}

final desktopPortCheckProvider =
    NotifierProvider<DesktopPortCheckNotifier, DesktopPortCheckState>(
      DesktopPortCheckNotifier.new,
    );

class DesktopEmergencyRestoreState {
  const DesktopEmergencyRestoreState({this.result, this.busy = false});

  final DesktopEmergencyRestore? result;

  final bool busy;
}

class DesktopEmergencyRestoreNotifier
    extends Notifier<DesktopEmergencyRestoreState> {
  @override
  DesktopEmergencyRestoreState build() =>
      const DesktopEmergencyRestoreState();

  Future<DesktopApiException?> restore() async {
    if (state.busy) return null;
    state = DesktopEmergencyRestoreState(result: state.result, busy: true);
    try {
      final result = await ref
          .read(desktopApiClientProvider)
          .emergencyRestore();
      if (ref.mounted) state = DesktopEmergencyRestoreState(result: result);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopEmergencyRestoreState(result: state.result);
      }
      return error;
    }
  }
}

final desktopEmergencyRestoreProvider =
    NotifierProvider<
      DesktopEmergencyRestoreNotifier,
      DesktopEmergencyRestoreState
    >(DesktopEmergencyRestoreNotifier.new);
