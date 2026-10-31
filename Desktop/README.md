# 谛听桌面端

## 工程组成

- `cmd/service/`、`internal/`：现有 Go DNS 核心、Windows 服务与平台能力。
- `flutter_frontend/`：Windows Wails 原生窗口使用的 Flutter UI 构建产物。
- `frontend/`：保留的 Vue 局域网 Web 控制台，由服务内嵌；与原生窗口资源相互独立。
- `../DITING-Flutter/lib/desktop/`：Flutter 桌面 UI 源码。

Flutter UI 通过现有本机 HTTP API 和 Wails App 绑定访问后端，不在 Dart 中复制 DNS 业务逻辑。

## 开发

界面预览：

```bash
cd ../DITING-Flutter
flutter run -d chrome -t lib/desktop/main.dart
```

单独构建 Flutter 桌面资源：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build_flutter_frontend.ps1
```

完整 Windows 构建（需要 Flutter 3.47+、Go 1.25+、Node.js 18+、Wails v2，打包还需 NSIS）：

```cmd
build.bat
```

Wails 会根据 `wails.json` 调用 Flutter 构建钩子；构建管理器会另外构建保留的 Web 控制台。

## 文档

桌面 UI 的完成范围、响应式规范、后端映射和后续路线见：

[`docs/development/flutter-desktop-ui.md`](../docs/development/flutter-desktop-ui.md)
