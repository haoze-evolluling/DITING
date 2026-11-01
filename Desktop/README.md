# README

## 前端来源

桌面窗口由 Wails 宿主（Go）加载 `frontend/dist`，该目录的内容现在是 **Flutter 桌面端**的 Web 构建产物：

- 源码：`../DITING-Flutter`（入口 `lib/desktop/main.dart`，路由与页面见 `../docs/development/flutter-desktop-ui.md`）
- 构建：`python build_frontend.py`，由 `wails.json` 的 `frontend:build` 调用；`frontend:install` 只做 `flutter pub get`
- 旧的 Vue 源码仍保留在 `frontend/src` 供对照，但不再参与构建

## 开发

前端热重载在浏览器里进行：

```bash
cd ../DITING-Flutter
flutter run -d chrome -t lib/desktop/main.dart
```

需要连同 Go 服务一起调试时，先启动 `diting-service`，再运行上面的命令；桌面壳（侧栏、窗口尺寸、安装包）仍由 Wails 提供。

## 构建

```bash
wails build
```

Wails 会先执行 `python build_frontend.py`（清空并重建 `frontend/dist`），再编译并嵌入资源。
