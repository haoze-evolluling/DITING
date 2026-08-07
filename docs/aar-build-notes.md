# Go AAR 构建记录

本文记录 DNSSR 项目本次 Go 隧道 AAR 的编译过程、构建参数、遇到的问题及解决办法，便于后续重新生成 `app/libs/tunnel.aar`。

## 构建目标

- 输出文件：`app/libs/tunnel.aar`
- Android 架构：仅 `arm64-v8a`（ARMv8-A）
- Android 最低 API：24
- AAR：启用 ZIP 压缩
- Go 二进制：移除符号表和调试信息
- 构建路径：启用 `-trimpath`

## 环境要求

需要安装并配置以下工具：

- Go
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

在项目的 `tunnel` 目录执行：

```powershell
$env:ANDROID_HOME = "D:\Androidsdk"
$env:ANDROID_SDK_ROOT = "D:\Androidsdk"
$env:GOFLAGS = "-buildvcs=false"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

gomobile bind `
  -target=android/arm64 `
  -androidapi 24 `
  -trimpath `
  -ldflags="-s -w" `
  -o ..\app\libs\tunnel.aar .
```

`gomobile bind` 生成的 AAR 会自动使用 ZIP 压缩。`-target=android/arm64` 确保不会生成 ARM32、x86 或 x86_64 库；`-s -w` 用于移除 Go 符号表和 DWARF 调试信息。

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

最终 AAR 约为 4.8 MB，内部只包含：

```text
jni/arm64-v8a/libgojni.so
```

可以使用以下命令查看 AAR 内容：

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead("app\libs\tunnel.aar")
$zip.Entries | Select-Object FullName, Length, CompressedLength
$zip.Dispose()
```

确认没有其他 `jni/*` 架构目录，并确认 `CompressedLength` 小于对应文件的 `Length`，即可验证架构和压缩结果。

