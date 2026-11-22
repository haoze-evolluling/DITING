library;

import 'package:diting_android/data/native/permissions_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final permissionsBridgeProvider = Provider<PermissionsBridge>(
  (ref) => PermissionsBridge(),
);

class PermissionStatesNotifier extends AsyncNotifier<PermissionSnapshot> {
  @override
  Future<PermissionSnapshot> build() =>
      ref.read(permissionsBridgeProvider).states();

  Future<void> refresh() async {
    state = AsyncData(await ref.read(permissionsBridgeProvider).states());
  }

  Future<PermissionSnapshot> request(AppPermission permission) async {
    final snapshot = await ref
        .read(permissionsBridgeProvider)
        .request(permission);
    state = AsyncData(snapshot);
    return snapshot;
  }

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
