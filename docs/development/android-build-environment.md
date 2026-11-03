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

## 版本上限（为什么没有更高）

Flutter 3.50 的工具链白名单写死在 SDK 里
（`packages/flutter_tools/lib/src/android/gradle_utils.dart`）：

```dart
const maxKnownAndSupportedGradleVersion = '9.5.0';
const maxKnownAndSupportedKgpVersion    = '2.4.20';  // 更高的版本按“已知范围内”放行
const maxKnownAndSupportedAgpVersion    = '9.4';
```

- **Gradle 9.5.0 就是上限**：`validateGradleAndAgp` 对 AGP 9.3.x 要求 Gradle 落在 `[9.5.0, 9.5.0]`，
  9.6/9.8.2 会被 `flutter analyze --suggestions` 判为不兼容（实测 9.8.2 仍能配置成功，
  但不在 Flutter 的支持范围内，且 Flutter Gradle 插件会多出编译告警）。
- **AGP 只能到 9.3.x**：9.4.1 起要求 Gradle ≥ 9.6.0，直接报
  `Minimum supported Gradle version is 9.6.0`，而 Gradle 又被 Flutter 卡在 9.5.0。9.3.3 是 9.3 线最后一个补丁。
- **Kotlin 可以更新**：高于 2.4.20 的 KGP 被 Flutter 视为“未知但有效”直接放行，故取 `2.4.21`。

升级 Flutter 时这三处要一起看：版本下限写在
`packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt`（低于下限直接构建失败），
模板默认值与上限写在上面那个 `gradle_utils.dart`。

## gradle.properties 的两个开关

```properties
android.builtInKotlin=true
android.newDsl=true
```

- **必须显式写出来**：Flutter 工具的 project migrator
  （`packages/flutter_tools/lib/src/android/migrations/`）在属性缺失时，每次构建都会往
  `gradle.properties` 追加 `android.builtInKotlin=false` / `android.newDsl=false`。写上（值任意）
  就会被跳过。
- `android.builtInKotlin=true`：由 AGP 内置 Kotlin 编译，KGP 只在构建 classpath 上提供编译器版本
  （`settings.gradle.kts` 里 `apply false` 的那条）。不这样写就得应用 KGP，AGP 9 会报
  `Deprecated 'org.jetbrains.kotlin.android' plugin usage`。
- `android.newDsl=true`：Flutter 3.47 的 Gradle 插件会强转 `AbstractAppExtension`，只能关掉新 DSL；
  **Flutter 3.50 起插件改用 `com.android.build.api.dsl.ApplicationExtension`**，可以打开，
  否则 AGP 提示 `The option setting 'android.newDsl=false' is deprecated`。

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
用 init 脚本的 `beforeSettings` 给复合构建里的每个 Settings 注入仓库。

实测速度（2026-11，本机，单线程下载 25 MB 的 `kotlin-gradle-plugin` jar）：

| 镜像 | 平均速度 | Central 制品 | Google（AGP）制品 |
| --- | --- | --- | --- |
| `https://repo.huaweicloud.com/repository/maven/` | 6.2 MB/s | ✅ | ✅ |
| `https://maven.aliyun.com/repository/public` | 5.0 MB/s | ✅ | ❌（需另加 `/google`） |
| `https://cache-redirector.jetbrains.com/maven-central` | 4.9 MB/s | ✅ | ❌ |
| `https://mirrors.cloud.tencent.com/nexus/repository/maven-public/` | 2.0 MB/s | ✅ | ✅ |
| `https://repo.maven.apache.org/maven2` | — | ❌ 403 | ❌ |

所以 init 脚本以华为云为主、腾讯云兜底（两者都能同时代理 Central 与 Google 仓库）。

Gradle 发行包同理不再走 `services.gradle.org`（1.1 MB/s），wrapper 指向
`https://mirrors.cloud.tencent.com/gradle/`（8.2 MB/s）。

## 应用侧依赖

- `material_ui 1.9.0`、`qr 4.0.1`（2026-11 已升到 pub 上的最新版）。
- `material_color_utilities` 与 `test_api` 被 Flutter 精确钉在旧版本：
  `flutter/pubspec.yaml` 钉 `material_color_utilities: 0.13.0`（上游 flutter/flutter#185017），
  `flutter_test/pubspec.yaml` 钉 `test_api: 0.7.14`。工作区根 `pubspec.yaml` 用
  `dependency_overrides` 把两者提到 `0.13.1` / `0.7.15`，不改 SDK 检出、`flutter upgrade`
  也不会冲突。注意：
  - `flutter pub get` 会以 `!` 标记这两个 overridden 版本，属正常输出；
  - `test_api` 是 `flutter_test` 的紧邻内部依赖，**升级 `flutter_test` 所在的 Flutter 版本时
    要先用 `flutter test` 复验**，确认没问题再把 override 改/删；
  - 等 Flutter 自身的约束放宽后，删掉对应 override 与 `shared/pubspec.yaml` 的版本号即可。
