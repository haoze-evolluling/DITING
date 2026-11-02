# Build Directory

该目录存放谛听 Windows / Linux 的打包资源与构建产物。

## 结构

- `bin/`：构建产物（不入库）。Windows 输出 `DITING-*-v*.exe` 安装包，Linux 输出 `.deb`。
- `appicon.png`：安装包与文档使用的品牌图。
- `windows/`：NSIS 安装包脚本与图标。
  - `icon.ico`：安装包与快捷方式图标。
  - `installer/project.nsi`：安装包主脚本，打包 Flutter 桌面端与 `diting-service.exe`。
  - `app/`：构建时暂存的 Flutter Windows Release 产物（构建结束自动清理）。
- `linux/`：systemd 单元、安装/卸载脚本与窗口图标。

## Windows

`project.nsi` 由 `../../maintenance/core/build_manager.py` 调用，需要两个宏：

- `ARG_APP_DIR`：Flutter Windows 产物目录（含 `diting_desktop.exe`、`data/` 等）。
- `ARG_SERVICE_BINARY`：`diting-service.exe` 路径。

安装包会注册并启动 `DitingDNSService`，卸载时停止服务、恢复网卡 DNS 并清理快捷方式。
WebView2 不再是运行依赖：桌面窗口由 Flutter 原生渲染。

## Linux

`build_linux.sh --package` 使用 `linux/` 下的文件组装 `.deb`；安装后由 systemd 托管
`diting-service`，Web 控制台随二进制内嵌。
