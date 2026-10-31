import 'package:diting/desktop/data/desktop_backend.dart';
import 'package:diting/desktop/data/desktop_models.dart';
import 'package:diting/desktop/data/desktop_native_bridge.dart';

DesktopNativeBridge createDesktopNativeBridge() =>
    const _UnavailableNativeBridge();

class _UnavailableNativeBridge implements DesktopNativeBridge {
  const _UnavailableNativeBridge();

  @override
  bool get isAvailable => false;

  Never _unavailable() =>
      throw const DesktopBackendException('当前平台没有 Wails 原生桥接。');

  @override
  Future<String> getPlatform() => _unavailable();
  @override
  Future<CoreServiceStatus> getCoreServiceStatus() => _unavailable();
  @override
  Future<bool> isAutoStartEnabled() => _unavailable();
  @override
  Future<bool> setAutoStart(bool enabled) => _unavailable();
  @override
  Future<String> installAndStartCoreService() => _unavailable();
  @override
  Future<String> restartCoreService() => _unavailable();
  @override
  Future<String> runEmergencyRestore() => _unavailable();
  @override
  Future<String> startCoreService() => _unavailable();
  @override
  Future<String> stopCoreService() => _unavailable();
}
