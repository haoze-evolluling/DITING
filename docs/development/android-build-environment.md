# Android 构建环境

Android 客户端（`android/app`）的 Gradle 工具链版本、必须的参数，以及本机网络下的依赖镜像配置。

## 工具链版本

| 组件 | 版本 | 位置 |
| --- | --- | --- |
| Flutter | `3.50.0-0.3.pre`（beta 频道，Dart 3.14.0） | 本机 SDK |
| Gradle | `9.5.0` | `android/app/android/gradle/wrapper/gradle-wrapper.properties` |
| AGP（`com.android.application`） | `9.3.3` | `android/app/android/settings.gradle.kts` |
| Kotlin（内置 Kotlin） | `2.4.21` | 同上，`org.jetbrains.kotlin.android ... apply false` |
| JDK | 17+（AGP 9 要求） | `flutter config --jdk-dir` 或 Android Studio 自带 JBR |

Flutter 3.50 的工具链白名单写死在 SDK 的 `gradle_utils.dart`（`packages/flutter_tools/lib/src/android/`）：
Gradle `9.5.0`、KGP `2.4.20`（更高版本按“已知范围内”放行）、AGP `9.4`。

- **Gradle 9.5.0 是上限**：AGP 9.3.x 要求 Gradle 恰为 `[9.5.0, 9.5.0]`，9.6/9.8.2 会被
  `flutter analyze --suggestions` 判为不兼容。
- **AGP 只能到 9.3.x**：9.4.1 起要求 Gradle ≥ 9.6.0，与上一条冲突；9.3.3 是 9.3 线最后补丁。
- **Kotlin 可以更新**：高于 2.4.20 的 KGP 被放行，故取 `2.4.21`。

升级 Flutter 时三处一起看：下限在 `DependencyVersionChecker.kt`（`packages/flutter_tools/gradle/`，
低于下限直接构建失败），默认值与上限在 `gradle_utils.dart`。

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

- `material_ui ^1.11.0`、`qr ^4.0.1`（其余依赖均使用 caret 范围，见各包 `pubspec.yaml`）。
- Flutter SDK 把 `material_color_utilities`（`0.13.0`，上游 flutter/flutter#185017）与 `test_api`
  （`0.7.14`）钉在旧版；本工作区不再用 `dependency_overrides` 强行提升，直接跟随 SDK 的锁定版本。
- `test_api` 是 `flutter_test` 的紧邻内部依赖：升级 Flutter 后先用 `flutter test` 复验；一旦 SDK
  放宽了对这两个包的约束，再按需提升 `shared/pubspec.yaml` 中的 `material_color_utilities` 约束。

## 跑测试（native assets 与资源包）

`flutter test` 要在各个 app 目录里跑：

```bash
cd android/app && flutter test     # Android 全量（含 sqflite 用例）
cd desktop/app && flutter test     # 桌面全量
```

从工作区根目录跑 `flutter test android/app` 会踩两个坑，都是 `flutter_tools` 按“当前包的依赖图”
解析造成的，不是本项目配置写错：

1. **原生依赖不编译**：hook 只为当前包（根包 `diting_workspace`，自身没有依赖）的传递依赖编译，
   于是日志里是 `No packages with native assets. Skipping native assets compilation.`，
   `build/native_assets/windows/native_assets.json` 写成空表，所有 sqflite 用例在
   `Couldn't resolve native function 'sqlite3_initialize'` 上失败。
2. **资源包不同**：测试资源包（`build/unit_test_assets`）也只装当前包声明的资源，从根跑时
   `packages/diting_shared/assets/https_passthrough.txt` 加载不到，`bootstrapRules` 的种子白名单
   用例会失败（日志：`preset whitelist asset missing`）。

sqlite3 的原生库由它自己的 build hook 下载，需要先开一次开关（机器本地设置，不在仓库里）：

```bash
flutter config --enable-native-assets
```

没开时 `flutter test` 会直接退出并提示 `Package(s) sqlite3 require the dart assets feature to be
enabled`。开关打开后，第一次跑测试时 hook 会按根 `pubspec.yaml` 的 `hooks.user_defines`
（GitHub release 走 `gh-proxy.com` 镜像）下载 `sqlite3.dll` / `libsqlite3.so` 到
`.dart_tool/hooks_runner/shared/sqlite3/build/`，之后复用；删掉 `.dart_tool/` 会重新下载。

本机验收（2026-11，`cd android/app && flutter test`）：514 通过、3 跳过。
