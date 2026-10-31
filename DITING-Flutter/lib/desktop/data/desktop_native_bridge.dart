import 'package:diting/desktop/data/desktop_models.dart';

/// Native operations exposed by the existing Wails App bindings.
/// Implementations are platform-specific so VM widget tests stay JS-free.
abstract class DesktopNativeBridge {
  bool get isAvailable;
  Future<String> getPlatform();
  Future<CoreServiceStatus> getCoreServiceStatus();
  Future<bool> isAutoStartEnabled();
  Future<bool> setAutoStart(bool enabled);
  Future<String> startCoreService();
  Future<String> stopCoreService();
  Future<String> restartCoreService();
  Future<String> installAndStartCoreService();
  Future<String> runEmergencyRestore();
}
