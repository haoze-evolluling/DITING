# Desktop Service（desktop/service）

Windows / Linux 服务端工程：Go 特权核心 `diting-service` 与内嵌的局域网 Web 控制台产物。

## 组成

- `cmd/service/`：核心服务入口（Windows Service / Linux systemd）。
- `internal/`：DNS 内核、平台适配、IPC、鉴权、查询日志。
- `frontend/embed.go`：把 `frontend/dist` 嵌入二进制，由服务在 15353 端口提供控制台。
- `frontend/dist/`：构建产物（不入库），由 `build_frontend.py` 从 `../app` 生成。
- `build/`：NSIS 安装包与 Linux 打包脚本，产物在 `build/bin/`。

桌面窗口（`../app`）只是客户端，通过本地 IPC（默认 `127.0.0.1:15353`）读取状态，与服务端共用同一套
Flutter 页面；维护工具箱在 `../toolbox`。

## 开发

编译前必须先生成 `frontend/dist`（服务通过 embed 引用）：

```bash
python build_frontend.py
go build -o build/bin/diting-service.exe ./cmd/service
build\bin\diting-service.exe -run      # 管理员权限；前台运行，关掉即停止
```

版本号不写在 Go 源码里：`build_installer.bat` / `build_linux.sh` 从 `../app/pubspec.yaml`
（唯一真源）取值后以 `-ldflags -X main.Version=...` 注入；直接 `go build` 的二进制版本显示为 `dev`，
仅用于调试。

浏览器打开 `http://127.0.0.1:15353` 即为 Web 控制台；桌面窗口用
`cd ..\app && flutter run -d windows`，打安装包用 `..\build_installer.bat`。

要求 Go 1.25+；Windows 打包用 Flutter 3.50+ 与 NSIS（可选）。

## 打包

`build.bat` 调用 `../toolbox/core/build_manager.py`，依次构建 Web 控制台、Flutter Windows 桌面端、
`diting-service.exe` 与 NSIS 安装包，产物在 `build/bin/DITING-*-v*.exe`。

```bash
./build_linux.sh --package            # 当前架构
./build_linux.sh -a arm64 --package   # amd64 / arm64 / arm
```

Windows 上可用 `build_deb.bat` 打包：本机交叉编译 Linux 二进制，WSL 只负责 `dpkg-deb` 组装。
安装、卸载与 systemd 单元见 `build/linux/install.sh`、`build/linux/uninstall.sh` 与
[`build/README.md`](build/README.md)。
