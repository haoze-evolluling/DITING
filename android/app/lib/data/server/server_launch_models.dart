library;

/// 服务器进程的启动与保活选项，保存在 Android 侧的 SharedPreferences 中。
class ServerLaunchSettings {
  const ServerLaunchSettings({this.autoStart = false, this.autoRestart = true});

  /// 设备重启或应用更新后自动启动服务器。
  final bool autoStart;

  /// 进程意外退出后自动重新拉起。
  final bool autoRestart;

  factory ServerLaunchSettings.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    return ServerLaunchSettings(
      autoStart: map['autoStart'] == true,
      autoRestart: map['autoRestart'] != false,
    );
  }

  ServerLaunchSettings copyWith({bool? autoStart, bool? autoRestart}) =>
      ServerLaunchSettings(
        autoStart: autoStart ?? this.autoStart,
        autoRestart: autoRestart ?? this.autoRestart,
      );

  @override
  bool operator ==(Object other) =>
      other is ServerLaunchSettings &&
      other.autoStart == autoStart &&
      other.autoRestart == autoRestart;

  @override
  int get hashCode => Object.hash(autoStart, autoRestart);
}
