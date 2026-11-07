# Go AAR 构建记录

Go 隧道引擎已迁至 `android/engine`（与 Android 客户端并列）。日常重建直接运行
`android/engine/build_aar.ps1`，本文记录等价的手工命令、参数与常见问题。

## 构建目标

| 架构 | 目标平台 | 输出（`android/app/android/app/libs/`） | 用途 |
| --- | --- | --- | --- |
| arm64-v8a（默认） | `android/arm64` | `tunnel-arm64.aar` | 真机 release（历史默认名 `tunnel.aar`） |
| x86_64 | `android/amd64` | `tunnel-x64.aar` | x86_64 模拟器 |
| 双 ABI（all） | `android/arm64,android/amd64` | `tunnel-all.aar` | debug 包，一个包通吃真机与模拟器 |

三种 AAR 都是构建产物，根 `.gitignore` 忽略 `*.aar`，全新克隆后首次打包前必须先生成。
`build.gradle.kts` 按 `-PditingAbi` / `--target-platform` 自动选用：debug 用 `tunnel-all`，
release 用 `tunnel-arm64`，`-PditingAbi=x86_64` 用 `tunnel-x64`，`-PtunnelAar=<路径>` 显式覆盖；
文件缺失会在 Gradle 配置期报错并提示生成命令。

公共参数：`-androidapi 28`（最低 Android 9.0，同时写入 AAR 的 `minSdkVersion`）、`-trimpath`、
`-ldflags="-s -w"`（去掉符号表与调试信息）；`gomobile bind` 生成的 AAR 自动使用 ZIP 压缩。

## 环境要求

Go 1.25+、`gomobile`、Android SDK 与 NDK、JDK 17+。`gomobile` 依赖以下变量：

```powershell
$env:ANDROID_HOME = "D:\Androidsdk"
$env:ANDROID_SDK_ROOT = "D:\Androidsdk"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
$env:GOFLAGS = "-buildvcs=false"
```

## 手工构建

在 `android/engine` 目录执行：

```powershell
gomobile bind `
  -target=android/arm64 `
  -androidapi 28 `
  -trimpath `
  -ldflags="-s -w" `
  -o ..\app\android\app\libs\tunnel-arm64.aar .
```

双 ABI 包用逗号分隔 target（`-target=android/arm64,android/amd64`），gomobile 会把两个 `jni/`
架构目录打进同一个 AAR。

## 与 Rust 内核的关系

AAR 里的 Go 引擎会在运行时 `dlopen("libditing_policy_core.so")`（域名规则判定）、
`dlopen("libditing_dns_cache_core.so")`（DNS 缓存容器、取值与改写）、
`dlopen("libditing_mitm_core.so")`（MITM 拦截过滤、黑名单与失败计数）、
`dlopen("libditing_cosmetic_core.so")`（装饰注入的流式 `<head>` 扫描、主机名归一化与 `<link>` 标签）与
`dlopen("libditing_resolver_core.so")`（上游统计：SRTT/RTTVAR、失败率、连败惩罚、熔断与三种自适应
延迟）、`dlopen("libditing_dns_core.so")`（上游空答案判定与按域名的动态阻断升级）与
`dlopen("libditing_sniffer_core.so")`（TLS ClientHello 的 SNI 走法、HTTP 方法门禁与 `Host` 头）与
`dlopen("libditing_bootstrap_core.so")`（引导解析的端点健康、加权选择与主机缓存）与
`dlopen("libditing_allowlist_core.so")`（严格应用白名单的域名走法与 TTL 授权）与
`dlopen("libditing_connlog_core.so")`（连接日志的键构造与有界去重）与
`dlopen("libditing_ipcache_core.so")`（IP→域名 LRU 与主机名提示），
把这十一块交给 Rust（见 `rust/README.md`）。这十一个 `.so` 与 AAR 无关，它们和 Flutter 侧的 `libditing_rule_core.so`
一起由 `python rust/build_android.py` 拷进
`android/app/android/app/src/main/jniLibs/<abi>/`，最终落在 APK 的 `lib/<abi>/`，正好在应用命名
空间的库搜索路径上。

因此打包顺序是：`python rust/build_android.py` → `build_aar.ps1` → `flutter build`。少了策略
`.so` APK 依然能装，但 `ApplyRuleSnapshot` 会失败，隧道启动直接报错（Go 侧已没有第二套判定实现）；
少了 DNS 缓存 `.so` 则缓存全部 miss，答案仍然正确；少了 MITM 过滤 `.so` 则 MITM 启动报错，
隧道照常运行但不再解密（Go 侧同样没有第二套过滤实现）；少了装饰注入 `.so` 则 MITM 同样启动报错，
不会退化成“拦截了但页面没拿到样式表”；少了统计 `.so` 则所有上游按冷启动取值参与调度；少了
应答 `.so` 则上游空答案按普通应答记日志、动态升级关闭；少了流嗅探 `.so` 则 MITM 同样启动报错，
直连回退只是少了 SNI 的主机名提示；少了引导解析 `.so` 则加密 DNS 主机名走普通系统解析路径；
少了应用白名单 `.so` 则被选中的 UID 转 fail-closed（拒绝 DNS 与连接），未选中的应用与
未配置规则时不受影响；少了连接日志去重 `.so` 则不再去重（日志更吵，事件不变）；
少了 IP→域名缓存 `.so` 则直连 IP 的流没有主机名提示。
统计、应答、引导解析、去重与 IP→域名缓存五个不改变答案。`rust/verify.py --go` 是构建前发现“没带上”的
地方。

## 常见问题

- **找不到 Android SDK**：`gomobile` 默认查找 `%LOCALAPPDATA%\Android\sdk`，不存在时需显式设置
  `ANDROID_HOME` / `ANDROID_SDK_ROOT`。
- **VCS stamping 失败**（`error obtaining VCS status`）：gomobile 临时工程读不到 VCS 状态，设置
  `GOFLAGS=-buildvcs=false` 即可，仅影响当前进程。
- **找不到 `javac`**：设置 `JAVA_HOME` 并把 `$JAVA_HOME\bin` 加入 `PATH`。

## 产物检查

`tunnel-arm64.aar` 约 4.8 MB，只含 `jni/arm64-v8a/libgojni.so`；`tunnel-all.aar` 约为其两倍，
包含 `jni/arm64-v8a/` 与 `jni/x86_64/` 各一份。可用下面的命令确认架构与压缩：

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead("android\app\android\app\libs\tunnel-arm64.aar")
$zip.Entries | Select-Object FullName, Length, CompressedLength
$zip.Dispose()
```

`CompressedLength` 小于 `Length` 即表示压缩生效。
