# Desktop Service（desktop/service）

Windows / Linux 服务端工程：Go 特权核心 `diting-service` 与内嵌的局域网 Web 控制台产物。

## 组成

- `cmd/service/`：核心服务入口（Windows Service / Linux systemd）。
- `internal/`：DNS 内核、平台适配、IPC、鉴权、查询日志。
- `rust/diting-stamp-core`（仓库根 `rust/` 下）：`sdns://` 印章解析内核。
- `rust/diting-filter-core`（同上）：规则索引与判定内核（字典树、布隆预检、通配/正则表、
  `$denyallow=` 排除与 `$dnsrewrite` 选择），每次查询都走。
- `rust/diting-rewrite-core`（同上）：重写记录的取值解析与校验（类型表、MX/SRV/HTTPS/SVCB
  取值语法、目标域名判定），自定义重写规则与 `$dnsrewrite` 修饰符共用。

三个内核都由 Go 在运行期用纯 Go 动态加载（Windows `syscall.LazyDLL`，Linux `purego`），因此
**不需要 cgo，`CGO_ENABLED=0` 的交叉编译照旧**。库必须与二进制一起交付（安装包放到
`diting-service` 同目录 / `/usr/lib/diting/`），也可以用 `DITING_STAMP_CORE_LIB` /
`DITING_FILTER_CORE_LIB` / `DITING_REWRITE_CORE_LIB` 指定显式路径；缺库或 ABI 不符时解析印章、
构建规则索引、构造重写记录都直接报错，没有降级实现。
- `frontend/embed.go`：把 `frontend/dist` 嵌入二进制，由服务在 15353 端口提供控制台。
- `frontend/dist/`：构建产物（不入库），由 `build_frontend.py` 从 `../app` 生成。
- `build/`：NSIS 安装包与 Linux 打包脚本，产物在 `build/bin/`。

桌面窗口（`../app`）只是客户端，通过本地 IPC（默认 `127.0.0.1:15353`）读取状态，与服务端共用同一套
Flutter 页面；维护工具箱在 `../toolbox`。

## 开发

编译前必须先生成 `frontend/dist`（服务通过 embed 引用）：

```bash
python build_frontend.py
cd ../../rust && cargo build --release -p diting-stamp-core -p diting-filter-core -p diting-rewrite-core && cd -
go build -o build/bin/diting-service.exe ./cmd/service
build\bin\diting-service.exe -run      # 管理员权限；前台运行，关掉即停止
```

版本号不写在 Go 源码里：`build_installer.bat` / `build_linux.sh` 从 `../app/pubspec.yaml`
（唯一真源）取值后以 `-ldflags -X main.Version=...` 注入；直接 `go build` 的二进制版本显示为 `dev`，
仅用于调试。

浏览器打开 `http://127.0.0.1:15353` 即为 Web 控制台；桌面窗口用
`cd ..\app && flutter run -d windows`，打安装包用 `..\build_installer.bat`。

要求 Go 1.25+、Rust（`cargo`，编三个内核）；Windows 打包用 Flutter 3.50+ 与 NSIS（可选）。
`go test ./...` 会在 `rust/target/{release,debug}/` 找内核，先跑一次
`cd rust && cargo build --release` 即可，不需要安装到系统目录。内核是外部文件，Go 的测试缓存
看不见它的变化，验证时用 `go test -count=1 ./...`（`python rust/verify.py --desktop` 已经这样做）。

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
