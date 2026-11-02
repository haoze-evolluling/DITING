# README

## 前端来源

桌面窗口由 Wails 宿主（Go）加载 `frontend/dist`，该目录的内容现在是 **Flutter 桌面端**的 Web 构建产物：

- 源码：`../DITING-Flutter/apps/diting_desktop`（入口 `lib/main.dart`，路由与页面见 `../docs/development/flutter-desktop-ui.md`）
- 构建：`python build_frontend.py`，由 `wails.json` 的 `frontend:build` 调用；`frontend:install` 只做 `flutter pub get`
- 旧的 Vue 源码仍保留在 `frontend/src` 供对照，但不再参与构建

## 开发

前端热重载在浏览器里进行：

```bash
cd ../DITING-Flutter/apps/diting_desktop
flutter run -d chrome
```

要调试 Flutter 原生窗口，直接在 `DITING-Flutter` 下运行 `run_desktop.bat`（需要 Visual Studio C++ 工作负载）。

桌面窗口本身只是客户端，必须连得上核心服务 `diting-service.exe`（本地 IPC，默认 `127.0.0.1:15353`），
否则它会如实显示「连不上本机服务」。`run_desktop.bat` 会在启动前探测该端口：已在监听就复用；
`build\bin\diting-service.exe` 存在就提权拉起 `-run`；两者都没有则打印编译命令。手工准备：

```bash
cd Desktop
go build -o build/bin/diting-service.exe ./cmd/service
build\bin\diting-service.exe -run      # 管理员权限
```

桌面壳（侧栏、窗口尺寸、安装包）仍由 Wails 提供；正式安装包里的服务由 NSIS 安装为 Windows 服务，
不需要手动启动。

## 构建

```bash
wails build
```

Wails 会先执行 `python build_frontend.py`（清空并重建 `frontend/dist`），再编译并嵌入资源。
