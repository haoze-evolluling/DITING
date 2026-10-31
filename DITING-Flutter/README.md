# 谛听 Flutter 客户端

同一 Flutter 工程包含两个独立入口：

- `lib/main.dart`：Android 客户端，沿用原有原生通道、数据库与启动流程。
- `lib/desktop/main.dart`：桌面 UI，编译为 Web 后嵌入现有 Wails 容器，通过本机 Go API 与 Wails 绑定复用桌面后端。

## 桌面 UI 预览

```bash
flutter pub get
flutter run -d chrome -t lib/desktop/main.dart
```

浏览器预览只用于界面开发和真实本机 API 调试，不提供 Wails 原生服务管理桥接。正式桌面产物由仓库根目录的 `Desktop/build.bat` 构建。

桌面 UI 的完成范围、模块边界与迭代计划见 [`docs/development/flutter-desktop-ui.md`](../docs/development/flutter-desktop-ui.md)。
