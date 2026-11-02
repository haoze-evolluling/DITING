/// Permission state and requests for the onboarding step and the troubleshooting rows; the native
/// channel is the only source of truth, since none of these can be granted from Dart.
library;

import 'package:diting_android/data/native/permissions_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Replaceable so widget tests need no platform channel.
final permissionsBridgeProvider = Provider<PermissionsBridge>(
  (ref) => PermissionsBridge(),
);

/// Current state of every permission the app asks for. Kept alive so returning from a settings
/// screen shows the new value without a full reload.
class PermissionStatesNotifier extends AsyncNotifier<PermissionSnapshot> {
  @override
  Future<PermissionSnapshot> build() =>
      ref.read(permissionsBridgeProvider).states();

  /// Re-reads the native snapshot; called when the app resumes or a settings screen closes.
  Future<void> refresh() async {
    state = AsyncData(await ref.read(permissionsBridgeProvider).states());
  }

  /// Opens the system dialog (or settings screen) for [permission] and publishes the new state.
  Future<PermissionSnapshot> request(AppPermission permission) async {
    final snapshot = await ref
        .read(permissionsBridgeProvider)
        .request(permission);
    state = AsyncData(snapshot);
    return snapshot;
  }

  /// Last-resort hand-off when a request was permanently denied.
  Future<bool> openSystemSettings(AppPermission permission) {
    final bridge = ref.read(permissionsBridgeProvider);
    return permission == AppPermission.notification
        ? bridge.openNotificationSettings()
        : bridge.openAppSettings();
  }
}

final permissionStatesProvider =
    AsyncNotifierProvider<PermissionStatesNotifier, PermissionSnapshot>(
      PermissionStatesNotifier.new,
    );
