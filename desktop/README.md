# desktop/

谛听（DITING）桌面端专属代码：Flutter Windows 窗口、Go 特权服务、开发者维护工具箱与启动脚本。

```
desktop/
├── app/                    # Flutter Windows 桌面窗口 + web/（局域网 Web 控制台）
├── service/                # Go 特权服务 diting-service、IPC、内嵌 Web 控制台产物
├── toolbox/                # Python + PyWebView 开发者工具箱
└── run_desktop.bat         # 启动桌面端；release 参数用于构建
```

Flutter 工作区根在仓库根 `pubspec.yaml`，共享代码在 `../shared`。

## 常用命令

```bash
# 仓库根：解析整个 Flutter 工作区
flutter pub get
flutter analyze

# 桌面端（Windows 原生窗口）
desktop\run_desktop.bat            # debug，支持热重载
desktop\run_desktop.bat release    # 构建 Release EXE 并启动

# 只用浏览器预览桌面 UI（无需 Visual Studio）
cd desktop/app
flutter run -d chrome

# 桌面端测试
cd desktop/app
flutter test
```

桌面端依赖：Flutter 3.47+、Visual Studio「使用 C++ 的桌面开发」工作负载、Windows 开发者模式
（`start ms-settings:developers`，插件符号链接需要）。`flutter doctor -v` 中 Visual Studio
一栏为 OK 才可构建原生窗口。

### 桌面窗口需要本机服务

桌面窗口只是客户端：所有数值都来自特权服务 `diting-service.exe` 的本地 IPC
（默认 `127.0.0.1:15353`）。服务没起来时，窗口会如实显示「连不上本机服务」，不会伪造状态。

`run_desktop.bat` 启动前会先探测该端口：已在监听就复用；`desktop/service/build/bin/diting-service.exe`
存在则以管理员权限拉起它，再启动窗口；两者都没有时打印编译/启动命令后继续（窗口仍可打开，
但只能显示离线态）。端口改过可用环境变量覆盖探测：`set DITING_IPC_PORT=15354`。

手工准备服务（只需一次）：

```bash
cd desktop/service
go build -o build/bin/diting-service.exe ./cmd/service
build\bin\diting-service.exe -run      # 管理员权限；前台运行，关掉即停止服务
```

### 系统托盘

桌面窗口沿用旧版 Wails 端的行为：点击关闭按钮只把窗口隐藏到系统托盘（首次会弹一次气泡提示），
进程继续在后台运行；左键单击托盘图标恢复主界面。右键菜单提供打开/隐藏主界面、开机自启动开关、
核心服务状态与启动/停止/重启、退出程序。

托盘由 `app/windows/runner/tray/` 的原生代码实现（图标、菜单、SCM 与注册表调用），
不依赖 Flutter 首帧，因此开机自启写入的 `--minimized` 参数可以直接静默进入托盘。Dart 只通过
`diting/tray` 方法通道把当前语言的菜单文案推给原生侧（`app/lib/data/host/desktop_tray.dart`）。

Windows 窗口与 Web 控制台的图标资源都来自品牌矢量源，由 `toolbox/core/logo_generator.py`
统一导出（`app/windows/runner/resources/app_icon.ico`、`app/web/favicon.png`、`app/web/icons/*`），
不要手改位图。

## 构建与打包

Windows 安装包与 Linux `.deb` 由 `service/build.bat`、`service/build_deb.bat` 或
`toolbox/core/build_manager.py` 驱动，详见 [`service/README.md`](service/README.md)。

开发者工具箱可直接双击 `toolbox/run_maintenance.bat`，或从仓库根运行：

```bash
python -m pip install -r desktop/toolbox/requirements.txt
python desktop/toolbox/app.py
```
