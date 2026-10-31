# Go AAR 构建记录

本文记录 DITING 项目 Go 隧道 AAR 的编译过程、构建参数、遇到的问题及解决办法，便于后续重新生成 `DITING-Flutter/android/app/libs/` 下的 tunnel AAR。

> **2026-10 结构调整**：Go 隧道引擎源码已从 `DITING-Legacy/tunnel` 迁至 `DITING-Flutter/tunnel`
> （新版工程自含引擎源码与构建入口）。`DITING-Legacy/app/libs/tunnel.aar` 是迁移时的冻结副本，
> 旧版工程继续用它构建，不再随引擎更新。日常重建直接运行 `DITING-Flutter/tunnel/build_aar.ps1`，
> 下文的手工命令等价于该脚本。

## 构建目标

按目标架构产出三种 AAR（日常直接跑 `build_aar.ps1`，见下方参数）：

| 架构 | 目标平台 | 输出文件 | 入库 | 用途 |
| --- | --- | --- | --- | --- |
| arm64-v8a（默认） | `android/arm64` | `DITING-Flutter/android/app/libs/tunnel-arm64.aar` | 是 | 真机 release 安装包（历史默认名 `tunnel.aar`） |
| x86_64 | `android/amd64` | `DITING-Flutter/android/app/libs/tunnel-x64.aar` | 否 | x86_64 模拟器 release 安装包 |
| 双 ABI（all） | `android/arm64,android/amd64` | `DITING-Flutter/android/app/libs/tunnel-all.aar` | 否 | **debug APK 默认引擎**，一个包通吃真机与 x86_64 模拟器 |

打包 APK 时 `android/app/build.gradle.kts` 自动选用：

- **debug 构建**（`ditingAbi` 未显式指定）→ `tunnel-all.aar`，双 ABI，真机与模拟器同包通用；
- **release 构建**（默认）→ `tunnel-arm64.aar`；
- `-PditingAbi=x86_64`（配合 `--target-platform android-x64`）→ `tunnel-x64.aar`；
- `-PditingAbi=all` → `tunnel-all.aar`（release 也可打出双 ABI 包）；
- `-PtunnelAar=<路径>` 显式覆盖；文件缺失会在 Gradle 配置期直接报错并提示生成命令。

- Android 最低 API：28（Android 9.0，`-androidapi 28`）。该值同时是 AAR 清单里的 `minSdkVersion`，
  也是应用侧 `android/app/build.gradle.kts` 中 `minSdk = 28` 的来源：Go 引擎不再兼容更旧的系统版本，
  低于 API 28 的设备不允许安装。
- AAR：启用 ZIP 压缩
- Go 二进制：移除符号表和调试信息
- 构建路径：启用 `-trimpath`

脚本参数：`build_aar.ps1`（默认 arm64 → `tunnel-arm64.aar`）/ `-Arch x64`（→ `tunnel-x64.aar`）/ `-Arch all`（→ 双 ABI 一体包 `tunnel-all.aar`）。

## 环境要求

需要安装并配置以下工具：

- Go 1.23+
- `gomobile`
- Android SDK
- Android NDK（由 `gomobile` 编译 Android 原生库时使用）
- JDK 8 或更高版本；本次使用 Android Studio 自带的 JBR

本次使用的本机路径如下，其他机器需要替换成实际路径：

```powershell
$env:ANDROID_HOME = "D:\Androidsdk"
$env:ANDROID_SDK_ROOT = "D:\Androidsdk"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
```

## 构建命令

在项目的 `DITING-Flutter/tunnel` 目录执行（或直接运行同目录的 `build_aar.ps1`）：

```powershell
$env:ANDROID_HOME = "D:\Androidsdk"
$env:ANDROID_SDK_ROOT = "D:\Androidsdk"
$env:GOFLAGS = "-buildvcs=false"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

gomobile bind `
  -target=android/arm64 `
  -androidapi 28 `
  -trimpath `
  -ldflags="-s -w" `
  -o ..\android\app\libs\tunnel-arm64.aar .
```

`gomobile bind` 生成的 AAR 会自动使用 ZIP 压缩。`-target=android/arm64` 确保不会生成 ARM32、x86 或 x86_64 库；`-s -w` 用于移除 Go 符号表和 DWARF 调试信息。双 ABI 一体包用逗号分隔多 target（`-target=android/arm64,android/amd64`），gomobile 会把两个 `jni/` 架构目录打进同一个 AAR。

## 遇到的问题与解决办法

### 1. 找不到 Android SDK

首次执行时，`gomobile` 默认查找：

```text
C:\Users\leeha\AppData\Local\Android\sdk
```

该目录不存在，因此构建立即失败。解决办法是将 `ANDROID_HOME` 和 `ANDROID_SDK_ROOT` 指向实际 SDK 目录，本次为 `D:\Androidsdk`。

### 2. Go VCS stamping 失败

SDK 配置正确后，Go 编译阶段报错：

```text
error obtaining VCS status: exit status 128
Use -buildvcs=false to disable VCS stamping.
```

这是当前 Go 版本在构建临时 gomobile 工程时无法读取 VCS 状态导致的。通过设置：

```powershell
$env:GOFLAGS = "-buildvcs=false"
```

关闭 VCS 信息写入后即可继续编译。该设置只影响当前 PowerShell 进程。

### 3. 找不到 `javac`

之后 Java 包装类编译失败：

```text
exec: "javac": executable file not found in %PATH%
```

系统没有把 JDK 的 `bin` 目录加入 `PATH`。本机已安装 Android Studio 自带 JBR，因此设置 `JAVA_HOME` 并把其 `bin` 目录加入 `PATH` 后解决。

## 构建结果检查

最终 `tunnel-arm64.aar` 约为 4.8 MB，内部只包含：

```text
jni/arm64-v8a/libgojni.so
```

`tunnel-all.aar` 约为两倍大小，内部包含 `jni/arm64-v8a/libgojni.so` 与 `jni/x86_64/libgojni.so` 各一份。

可以使用以下命令查看 AAR 内容：

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead("DITING-Flutter\android\app\libs\tunnel-arm64.aar")
$zip.Entries | Select-Object FullName, Length, CompressedLength
$zip.Dispose()
```

确认没有其他 `jni/*` 架构目录，并确认 `CompressedLength` 小于对应文件的 `Length`，即可验证架构和压缩结果。

