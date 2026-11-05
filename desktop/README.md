# desktop/

谛听（DITING）桌面端代码：Flutter Windows 窗口、Go 特权服务、维护工具箱与安装包脚本。

```
desktop/
├── app/                    # Flutter Windows 桌面窗口 + web/（局域网 Web 控制台）
├── service/                # Go 特权服务 diting-service、IPC、内嵌 Web 控制台产物
├── toolbox/                # Python + PyWebView 维护工具箱
└── build_installer.bat     # 构建 Windows EXE / Linux deb
```

Flutter 工作区根在仓库根 `pubspec.yaml`，共享代码在 `../shared`。

## 常用命令

```bash
flutter pub get                  # 仓库根
cd desktop/app
flutter run -d windows          # 原生窗口
flutter run -d chrome           # 仅浏览器预览，无需 Visual Studio
flutter test
```

```bat
desktop\build_installer.bat            :: 只打 Windows EXE
desktop\build_installer.bat both       :: EXE + Linux deb（WSL 组装）
```

依赖 Flutter 3.50+、Visual Studio「使用 C++ 的桌面开发」工作负载与 Windows 开发者模式
（`start ms-settings:developers`，插件符号链接需要）。

## 版本号

`app/pubspec.yaml` 的 `version:` 是桌面端唯一天源 —— Flutter 构建必须从它读，服务端、NSIS 安装包
与 Linux deb 都由构建脚本在构建期从它取版本号注入，源码里不再存副本：

| 位置 | 版本号从哪来 |
| --- | --- |
| `app/pubspec.yaml` | 唯一真源，改这一行（或用 `service\set_version.bat 2.2.12`） |
| `service/cmd/service/main.go` | `go build -X main.Version=...`，直接 `go build` 显示 `dev` |
| `service/build/windows/installer/project.nsi` | `makensis -DINFO_PRODUCTVERSION=...`，缺参数直接报错 |
| `service/build_linux.sh` | 自己读 `../app/pubspec.yaml` |

`python toolbox/core/version_manager.py -s` 会列出真源与各个派生位置；谁把版本字面量写回派生位置，
这里会直接提醒。Android 客户端（根 `android/app/pubspec.yaml`）是独立版本线，不参与。

## 界面规范

桌面窗口的留白与层次由三处常量决定，改页面时先看它们，不要就地写新数字：

- `app/lib/widgets/desktop_spacing.dart`：4 基准的间距刻度（`AppGap`）。标题与说明、两块内容、
  两行表单字段、字段与其说明各用哪一档，注释里有对应用法。
- `app/lib/widgets/desktop_card_board.dart`：页边距 24、卡片间距 16、两列门槛 984（每列至少
  460 才放得下带状态徽标与开关的标题行）。页面一律走这张卡板，不要在卡板之外单独放一张满宽卡片。

  卡板的排布规则是硬标准，改页面时不要绕过：

  | 页面卡片数 | 卡板宽度 | 排布 |
  | --- | --- | --- |
  | 1–2 张 | 任意 | 单列，限宽 960 并居中（左右边距相等） |
  | 3 张及以上 | < 984 | 单列，占满卡板（只留 24 页边距） |
  | 3 张及以上 | ≥ 984 | 两列瀑布流，每张卡恰好占一列 |
  | 任意 | 显式传 `singleColumn: true` | 单列且占满卡板（卡片本身是网格或表格时用） |

  每张卡只占一列，不要为了凑两列而拆卡或加卡；需要整宽的表格/网格卡片传 `singleColumn`，
  不要把它放到卡板之外。这三个分支由 `app/test/desktop_card_board_test.dart` 逐个固定，
  改分支必须同时改规则说明。
- `shared/lib/widgets/dashboard/dashboard_style.dart`：卡片内边距与圆角、标题/说明字号。手机密度
  保持原值，桌面档的卡片是 24 圆角 + 24/22 内边距、15 号标题、13/1.45 说明。

截图是这类改动的验收方式：`app/test/screenshot/` 会渲染真实页面到 `build/screenshots/`，包含
两列/单列、深色、窄窗、放大字号与三个弹窗：

```bash
cd desktop/app
DITING_SCREENSHOTS=1 flutter test test/screenshot/desktop_screenshot_test.dart --update-goldens
```

改完间距或断点，先看截图再提交；只看代码判断不出「挤」还是「空」。

## 桌面窗口需要本机服务

窗口只是客户端，数值全部来自 `diting-service.exe` 的本地 IPC（默认 `127.0.0.1:15353`）；服务未启动
时窗口会如实提示连不上，不会伪造状态。`build_installer.bat` 只编译打包，不安装也不启动服务：

```bat
cd desktop\service
go build -o build/bin/diting-service.exe ./cmd/service
build\bin\diting-service.exe -run    :: 管理员权限，前台运行
```

端口变更（如 `set DITING_IPC_PORT=15354`）需要两端同时调整。

## 系统托盘

关闭按钮只隐藏窗口到托盘（首次弹一次气泡提示），进程继续运行；左键恢复主界面，右键菜单提供显示/隐藏、
开机自启、核心服务启停与退出。托盘由 `app/windows/runner/tray/` 的原生代码实现（不依赖 Flutter 首帧，
`--minimized` 可静默进入托盘），Dart 侧只通过 `diting/tray` 通道推送当前语言的菜单文案。
窗口与 Web 图标来自品牌矢量源，由 `toolbox/core/logo_generator.py` 导出，不要手改位图。

## 构建与打包

安装包由 `build_installer.bat`、`service/build.bat`、`service/build_deb.bat` 或
`toolbox/core/build_manager.py` 驱动，详见 [`service/README.md`](service/README.md)。
