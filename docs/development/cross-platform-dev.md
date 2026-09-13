# 跨平台开发指南（Windows / Linux）

「谛听」同时在 Windows 与 Linux 上开发。本文描述如何用**同一套命令和配置**在两个平台完成环境配置、编译、安装与调试，避免切换平台时重复改脚本或重新配置。

核心思路：

1. **平台差异全部收敛到根目录的 `dev.py`**：JDK(JBR)、Android SDK、ADB 的探测路径、环境变量设置按平台自动适配，Windows 与 Linux 均以 Python（标准库）为统一入口，只维护这一个脚本。
2. **机器相关路径不入库**：SDK/JDK 的本机路径只存在于环境变量、`local.properties`（已 gitignore）或用户级 `~/.gradle/gradle.properties` 中，仓库内不提交任何绝对路径。
3. **不依赖平台专用脚本**：原 Windows 专用的 `build_apk.bat` 已删除，其全部功能（交互菜单、无线 ADB 连接、设备选择、安装）都由 `dev.py` 承接。

## 统一入口 `dev.py`

在项目根目录执行，Windows（cmd / PowerShell）与 Linux（bash / zsh）命令完全一致：

```bash
python dev.py doctor [--fix]        # 环境体检；--fix 自动写 local.properties 的 sdk.dir
python dev.py build debug           # 编译 Debug APK
python dev.py build release --clean # Clean 后编译 Release APK
python dev.py install debug         # 安装到设备（支持无线 adb 连接 IP:PORT）
python dev.py install debug --device 192.168.1.1:6688
python dev.py gradle --version      # 透传 gradlew 任意参数
python dev.py adb logcat            # 透传 adb 任意命令
python dev.py aar                   # 重新编译 Go 隧道 AAR（tunnel -> app/libs/tunnel.aar）
python dev.py                       # 交互式菜单（需在终端运行）
```

Linux/macOS 下也可以直接执行 `./dev.py`（脚本带 shebang 且已保留可执行位）。

> 注意：请**在终端中运行** `python dev.py`（不带参数时显示交互菜单）。在文件管理器里双击运行没有终端附着，此时脚本会自动弹出一个新终端窗口运行菜单；若无法弹出终端（CI、无桌面环境等），脚本会直接退出并提示，**不会**在后台自动执行构建。

### 原 build_apk.bat 用法对照

| 原 build_apk.bat        | 现在的写法（两平台相同）                |
| ----------------------- | --------------------------------------- |
| 双击（交互菜单）        | `python dev.py`（在终端中）             |
| `build_apk.bat debug`   | `python dev.py build debug`             |
| `build_apk.bat release` | `python dev.py build release`           |
| `build_apk.bat clean`   | `python dev.py clean`                   |
| `clean debug`           | `python dev.py clean debug`             |
| （BAT 内）询问是否安装  | `python dev.py install debug`           |

交互式无线 ADB 连接（无设备时输入 `IP:PORT`）、多设备选择等原有体验完整保留在 `install` 与交互菜单中。

## 工具自动探测与平台差异适配

`dev.py` 按以下优先级探测，全部命中后无需手动设置任何环境变量：

| 工具 | 探测顺序 | Windows 默认位置 | Linux 默认位置 |
| ---- | -------- | ---------------- | -------------- |
| JDK  | `$JAVA_HOME` → Android Studio JBR → `~/.jdks` → PATH | `C:\Program Files\Android\Android Studio\jbr`、`%LOCALAPPDATA%\Programs\Android Studio\jbr` | `~/Applications/android-studio/jbr`、`/opt/android-studio/jbr`、`/usr/local/android-studio/jbr`、snap |
| SDK  | `$ANDROID_HOME` → `$ANDROID_SDK_ROOT` → `local.properties` → 默认位置 | `%LOCALAPPDATA%\Android\Sdk` | `~/Android/Sdk` |
| ADB  | SDK `platform-tools` → 系统 PATH | 同左 | 同左 |

`python dev.py gradle ...` 执行时若 `JAVA_HOME` 未设置或指向不存在的目录，会自动用探测到的 JBR 注入子进程环境，不污染系统。

## Gradle / JDK 版本约定

- `gradle/gradle-daemon-jvm.properties` 声明了 daemon JVM 要求：**JDK 25**，且已移除 Foojay 下载 URL，`gradle.properties` 中同时关闭了 toolchain 自动下载 —— Gradle **只会使用本机已安装的 JDK，不会自动下载**。
- 两个平台各装一次 Android Studio（自带 JBR 25）即可满足；`python dev.py doctor` 会校验版本是否匹配。
- 机器级兜底配置（可选，不入库）：Linux 可在 `~/.gradle/gradle.properties` 写 `org.gradle.java.home=<JBR路径>`；Windows 设置用户环境变量 `JAVA_HOME` 指向 JBR 即可。
- 新 clone 后若 Linux 下 `./gradlew` 报无执行权限：`chmod +x gradlew`（仓库已通过 git 记录可执行位，正常无需手动）。

## 首次配置（每个平台约 1 分钟）

1. 安装 Android Studio（自带 JBR 25 与 SDK 管理器），用 SDK Manager 装 Platform-Tools、Platform 36。
2. clone 项目后执行：

   ```bash
   python dev.py doctor --fix   # 自动写入 local.properties（Windows/Linux 均可）
   python dev.py build debug    # 验证构建
   ```

3. （可选，重新编译 Go 隧道 AAR 才需要）安装 Go 1.20+、NDK，然后 `go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init`，之后两平台统一使用：

   ```bash
   python dev.py aar
   ```

   该命令自动设置 `ANDROID_HOME`、`JAVA_HOME`、`PATH`、`GOFLAGS=-buildvcs=false` 并按 `docs/development/aar-build-notes.md` 的参数执行 `gomobile bind`，Windows/Linux 行为一致。手动 PowerShell 过程仍保留在 AAR 构建记录中备查。

## 行尾与换行约定（.gitattributes）

仓库已通过 `.gitattributes` 固定：`*.bat`/`*.cmd`/`*.ps1` 检出为 CRLF，`*.sh`/`*.py`/`gradlew` 检出为 LF。任何平台 checkout 后脚本均可直接运行，不会因行尾互相污染。

## CI 兼容性说明

- 构建入口始终是标准 `gradlew`，CI 无需 Python 也可构建；`dev.py` 只是本地开发的便捷层。
- CI 镜像需预装 **JDK 25**（daemon JVM criteria 不再自动下载 toolchain）。如 CI 依赖自动下载，需自行恢复 `gradle-daemon-jvm.properties` 中的 Foojay URL（不推荐）。
