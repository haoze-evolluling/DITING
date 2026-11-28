# Android 构建环境

Android 客户端（`android/app`）的 Gradle 工具链版本、必须的参数，以及本机网络下的依赖镜像配置。

## 工具链版本

| 组件 | 版本 | 位置 |
| --- | --- | --- |
| Flutter | `3.50.1`（stable 频道，Dart 3.14.0） | 本机 SDK |
| Gradle | `9.9.2` | `android/app/android/gradle/wrapper/gradle-wrapper.properties` |
| AGP（`com.android.application`） | `9.5.2` | `android/app/android/settings.gradle.kts` |
| Kotlin（内置 Kotlin） | `2.4.21` | 同上，`org.jetbrains.kotlin.android ... apply false` |
| JDK | 17+（AGP 9 要求） | `flutter config --jdk-dir` 或 Android Studio 自带 JBR |

Flutter 3.50.1 的工具链白名单写死在 SDK 的 `gradle_utils.dart`（`packages/flutter_tools/lib/src/android/`）：
模板默认 Gradle `9.5.0`、AGP `9.3.1`、KGP `2.4.20`；已知支持上限为 Gradle `9.5.0`、AGP `9.4`、
KGP `2.4.20`。

本工程使用 Gradle `9.9.2` + AGP `9.5.2`，两者都高于 Flutter 3.50.1 的已知上限，但校验仍通过：

- **超出已知范围的 AGP 按“假定有效”放行**：`validateGradleAndAgp` 对 AGP 高于 `9.4` 只要求
  Gradle ≥ `9.5.0`、不设上限，所以 Gradle `9.9.2` 可用。`flutter analyze --suggestions` 实测
  报告 `Java/Gradle/KGP/Android Gradle Plugin: compatible`（2026-11）。
- **Gradle 的上限取决于 AGP**：AGP 9.3.x 要求 Gradle 恰为 `[9.5.0, 9.5.0]`。若把 AGP 退回
  9.3.x，必须同时把 Gradle 降到 `9.5.0`；当前 AGP 9.5.2 + Gradle 9.9.2 不受这条约束。
- **Kotlin 版本检查被跳过**：启用 `android.builtInKotlin=true` 后，`DependencyVersionChecker`
  不再校验 KGP 版本，故 `org.jetbrains.kotlin.android` 取 `2.4.21`。`flutter analyze --suggestions`
  输出中的 `Could not parse kotlin version ... KGP Version: null` 即由此产生，可忽略。

升级 Flutter 时三处一起看：低于下限的版本在 `DependencyVersionChecker.kt`（`packages/flutter_tools/gradle/`，
直接构建失败），默认值与已知上限在 `gradle_utils.dart`。

## gradle.properties 的两个开关

```properties
android.builtInKotlin=true
android.newDsl=true
```

必须显式写出（值任意）：属性缺失时 Flutter 的 project migrator 每次构建都会追加
`android.builtInKotlin=false` / `android.newDsl=false`。前者让 AGP 内置 Kotlin 编译（KGP 只提供编译器
版本），否则 AGP 9 报 `Deprecated 'org.jetbrains.kotlin.android' plugin usage`；后者开启新 DSL，否则
AGP 提示 `android.newDsl=false is deprecated`。

## Maven 镜像（本机网络必需）

本机访问 Maven Central 返回 403，`plugins.gradle.org` 的制品请求也会 302 到 Central，所以依赖
必须走国内镜像。Flutter Gradle 插件本身是一个 included build
（`$flutterSdkPath/packages/flutter_tools/gradle`），它自己的 `settings.gradle.kts` 写死了
`google()` + `mavenCentral()` 且 `FAIL_ON_PROJECT_REPOS`，**应用侧 `settings.gradle.kts` 里的
仓库声明覆盖不到它**——只能在 init 脚本里配置。

```bat
:: 一次性安装到本机（Windows）
copy android\app\android\gradle\maven-mirror.init.gradle.kts %USERPROFILE%\.gradle\init.d\
```

仓库文件：[`android/app/android/gradle/maven-mirror.init.gradle.kts`](../../android/app/android/gradle/maven-mirror.init.gradle.kts)，
用 init 脚本的 `beforeSettings` 给复合构建里的每个 Settings 注入仓库。实测（2026-11，单线程下载
25 MB 的 `kotlin-gradle-plugin` jar）：

| 镜像 | 平均速度 | Central 制品 | Google（AGP）制品 |
| --- | --- | --- | --- |
| `https://repo.huaweicloud.com/repository/maven/` | 6.2 MB/s | ✅ | ✅ |
| `https://maven.aliyun.com/repository/public` | 5.0 MB/s | ✅ | ❌（需另加 `/google`） |
| `https://cache-redirector.jetbrains.com/maven-central` | 4.9 MB/s | ✅ | ❌ |
| `https://mirrors.cloud.tencent.com/nexus/repository/maven-public/` | 2.0 MB/s | ✅ | ✅ |
| `https://repo.maven.apache.org/maven2` | — | ❌ 403 | ❌ |

所以 init 脚本以华为云为主、腾讯云兜底（两者都能同时代理 Central 与 Google 仓库）。Gradle 发行包同理
不走 `services.gradle.org`（1.1 MB/s），wrapper 指向 `https://mirrors.cloud.tencent.com/gradle/`（8.2 MB/s）。

## 应用侧依赖

- `material_ui ^1.11.0`（其余依赖均使用 caret 范围，见 `android/app/pubspec.yaml`）。
- Flutter SDK 把 `material_color_utilities`（`0.13.0`，上游 flutter/flutter#185017）与 `test_api`
  （`0.7.14`）钉在旧版；本项目不再用 `dependency_overrides` 强行提升，直接跟随 SDK 的锁定版本。
- `test_api` 是 `flutter_test` 的紧邻内部依赖：升级 Flutter 后先用 `flutter test` 复验；一旦 SDK
  放宽了对这两个包的约束，再按需提升 `android/app/pubspec.yaml` 中的 `material_color_utilities` 约束。

## Android 原生产物

`rust/build_android.py` 为每个 ABI 输出一个文件，由 Gradle 的 `checkNativeLibs<Variant>` 检查：

| 文件 | 用途 |
| --- | --- |
| `libditing_native.so` | 隧道引擎与 Dart/Kotlin UI 内核的单一 cdylib |

服务器模式复用同一份内核在应用进程内解析 DNS，不再打包独立的服务器启动器。合并后原先分散在
引擎与服务器里的 DNS/TLS/HTTP 栈只保留一份，每个 ABI 的原生负载明显减小。缺少该文件时 Gradle
构建会直接失败。

服务器模式在 Android 上不能依赖 `rustls-native-certs`（没有 `/etc/ssl/certs` 汇总文件），
根证书由引擎读取 `/system/etc/security/cacerts` 与 Conscrypt APEX 目录，再附加内置 ISRG 根。

## 跑测试（native assets 与资源包）

`flutter test` 在 `android/app` 目录里跑：

```bash
cd android/app && flutter test     # Android 全量（含 sqflite 用例）
```

sqlite3 的原生库由它自己的 build hook 下载，需要先开一次开关（机器本地设置，不在仓库里）：

```bash
flutter config --enable-native-assets
```

没开时 `flutter test` 会直接退出并提示 `Package(s) sqlite3 require the dart assets feature to be
enabled`。开关打开后，第一次跑测试时 hook 会按 `android/app/pubspec.yaml` 的 `hooks.user_defines`
（GitHub release 走 `gh-proxy.com` 镜像）下载 `sqlite3.dll` / `libsqlite3.so` 到
`.dart_tool/hooks_runner/shared/sqlite3/build/`，之后复用；删掉 `.dart_tool/` 会重新下载。

本机验收（2026-11，`cd android/app && flutter test`）：682 通过、4 跳过。
