# DITING-Flutter

谛听 Flutter 工作区（pub workspace）：一份 lockfile，三个包。

```
DITING-Flutter/
├── packages/diting_shared/   # 共享设计系统、主题、l10n、旧版配置/SQLite 读取
├── apps/diting_android/      # Android 客户端：页面、路由、原生通道、android/、tunnel/
├── apps/diting_desktop/      # Windows 桌面端：原生 Flutter 窗口 + web/（局域网控制台）
├── run_desktop.bat           # 启动桌面端；release 参数用于打包
└── pubspec.yaml              # workspace 根
```

## 常用命令

```bash
# 工作区根：一次解析三个包
flutter pub get
flutter analyze

# Android
cd apps/diting_android
flutter test
build_apk.bat                 # 交互式打包（见仓库根 README）

# 桌面端（Windows 原生窗口）
DITING-Flutter\run_desktop.bat            # debug，支持热重载
DITING-Flutter\run_desktop.bat release    # 构建 Release EXE 并启动

# 只用浏览器预览桌面 UI（无需 Visual Studio）
cd apps/diting_desktop
flutter run -d chrome
```

桌面端依赖：Flutter 3.47+、Visual Studio「使用 C++ 的桌面开发」工作负载、Windows 开发者模式
（`start ms-settings:developers`，插件符号链接需要）。`flutter doctor -v` 中 Visual Studio
一栏为 OK 才可构建原生窗口。

### 桌面窗口需要本机服务

桌面窗口只是客户端：所有数值都来自特权服务 `diting-service.exe` 的本地 IPC
（默认 `127.0.0.1:15353`）。服务没起来时，窗口会如实显示「连不上本机服务」，不会伪造状态。

`run_desktop.bat` 启动前会先探测该端口：已在监听就复用；`Server\build\bin\diting-service.exe`
存在则以管理员权限拉起它，再启动窗口；两者都没有时打印编译/启动命令后继续（窗口仍可打开，
但只能显示离线态）。端口改过可用环境变量覆盖探测：`set DITING_IPC_PORT=15354`。

手工准备服务（只需一次）：

```bash
cd Server
go build -o build/bin/diting-service.exe ./cmd/service
build\bin\diting-service.exe -run      # 管理员权限；前台运行，关掉即停止服务
```

### 系统托盘

桌面窗口沿用旧版 Wails 端的行为：点击关闭按钮只把窗口隐藏到系统托盘（首次会弹一次气泡提示），
进程继续在后台运行；左键单击托盘图标恢复主界面。右键菜单提供打开/隐藏主界面、开机自启动开关、
核心服务状态与启动/停止/重启、退出程序。

托盘由 `apps/diting_desktop/windows/runner/tray/` 的原生代码实现（图标、菜单、SCM 与注册表调用），
不依赖 Flutter 首帧，因此开机自启写入的 `--minimized` 参数可以直接静默进入托盘。Dart 只通过
`diting/tray` 方法通道把当前语言的菜单文案推给原生侧（`lib/data/host/desktop_tray.dart`）。

Windows 窗口与 Web 控制台的图标资源都来自品牌矢量源，由 `maintenance/core/logo_generator.py`
统一导出（`windows/runner/resources/app_icon.ico`、`web/favicon.png`、`web/icons/*`），不要手改位图。

## 目录边界

- `diting_shared` 只允许放两个宿主都需要的代码：`lib/ui`（设计系统）、`lib/app`（主题/l10n）、
  `lib/l10n`（ARB 与生成文件）、`lib/data/prefs`、`lib/data/db` 中桌面也会编译到的读取层、
  `lib/widgets/dashboard` 等共享组件。资源与 shader 也在这里，代码里用
  `packages/diting_shared/assets/...` 引用。
- `apps/diting_android/lib/pages`、`routes`、`shell`、`overlay`、`data/native` 等只服务 Android。
- `apps/diting_desktop/lib` 只服务桌面窗口与 Web 控制台；不要反向依赖 `diting_android`。

## 本地化

ARB 与生成文件都在 `packages/diting_shared/lib/l10n`。修改 `app_zh.arb` / `app_en.arb` 后执行：

```bash
cd packages/diting_shared
flutter gen-l10n
```

## 测试

```bash
cd apps/diting_android && flutter test
cd apps/diting_desktop && flutter test
```

桌面自截图（写到 `apps/diting_desktop/build/screenshots/`，不入库）：

```bash
cd apps/diting_desktop
DITING_SCREENSHOTS=1 flutter test test/screenshot/desktop_screenshot_test.dart --update-goldens
```
