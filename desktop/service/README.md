# Desktop Service（desktop/service）

谛听（DITING）的 Windows / Linux 服务端工程：Go 特权核心服务 `diting-service`，以及供局域网
浏览器访问的 Flutter Web 控制台产物。

## 组成

- `cmd/service/`：特权核心服务入口（Windows Service / Linux systemd）。
- `internal/`：DNS 内核、平台适配、IPC、鉴权、查询日志。
- `frontend/embed.go`：把 `frontend/dist` 嵌入服务二进制，由服务在 15353 端口提供 Web 控制台。
- `frontend/dist/`：构建产物，不入库；由 `build_frontend.py` 从 `../app` 生成。
- `build/`：NSIS 安装包、Linux systemd 打包脚本与构建产物。

桌面窗口（`../app`）只是客户端：它通过本地 IPC（默认 `127.0.0.1:15353`）读取服务状态，
与服务端共用同一套 Flutter 页面。开发者工具箱位于 `../toolbox`。

## 开发

```bash
# 构建 Web 控制台产物（服务编译前必须先有 frontend/dist）
python build_frontend.py

# 运行特权服务（管理员权限 / root）
go build -o build/bin/diting-service.exe ./cmd/service
build\bin\diting-service.exe -run
```

浏览器打开 `http://127.0.0.1:15353` 即可使用 Web 控制台；桌面窗口从源码运行时
`cd ..\app && flutter run -d windows`，打安装包用 `..\build_installer.bat`。

## Windows 安装包

要求 Go 1.25+、Flutter 3.47+、NSIS（可选）。

```cmd
build.bat
```

`build.bat` 调用 `../toolbox/core/build_manager.py`，依次构建：

1. Flutter Web 控制台产物（`frontend/dist`）
2. Flutter Windows 桌面端（`../app`）
3. 特权服务 `diting-service.exe`
4. NSIS 安装包

产物输出至 `build/bin/DITING-*-v*.exe`。手动编译服务与桌面端：

```cmd
go build -ldflags "-s -w -H windowsgui" -o build/bin/diting-service.exe ./cmd/service

cd ..\app
flutter build windows --release
```

## Linux

```bash
./build_linux.sh --package            # 当前架构
./build_linux.sh -a arm64 --package   # 指定 amd64 / arm64 / arm
```

在 Windows 上可通过 `build_deb.bat` 打包：本机 Go 交叉编译 Linux 二进制，WSL 仅用
`dpkg-deb` 组装。安装与卸载见 `build/linux/install.sh`、`build/linux/uninstall.sh`。
