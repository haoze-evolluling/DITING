# android/

谛听（DITING）Android 端专属代码。

```
android/
├── app/                    # Flutter 客户端：lib/、test/、原生壳、build_apk.bat
│   ├── android/            # Gradle / Kotlin / VpnService / 快捷磁贴 / 悬浮窗
│   └── build_apk.bat       # 交互式 APK 打包（Debug/Release、ARM64/x86_64、清理）
└── engine/                 # Go 隧道引擎源码（gomobile 编译为 AAR）
    └── build_aar.ps1       # 生成 tunnel-arm64 / x64 / all.aar
```

Flutter 工作区根在仓库根 `pubspec.yaml`，共享代码在 `../shared`。

## 常用命令

```bash
flutter pub get      # 仓库根：解析整个工作区
flutter analyze
cd android/app && flutter test
android\app\build_apk.bat
```

要求 Flutter 3.50+、JDK 17+、Android SDK；最低 Android 9.0（API 28）。工具链版本上限与 Maven
镜像见 [`docs/development/android-build-environment.md`](../docs/development/android-build-environment.md)。

## 隧道引擎 AAR

三种工作模式共用 `engine/` 的同一套 Go 引擎，差异只在 TUN 路由范围：极速模式仅接管 DNS，普通模式
接管全网络，服务器模式不建隧道。AAR 是构建产物、不入库，首次打包前先生成：

```powershell
cd android/engine
pwsh -File build_aar.ps1            # arm64（release 默认）
pwsh -File build_aar.ps1 -Arch x64  # x86_64 模拟器
pwsh -File build_aar.ps1 -Arch all  # 双 ABI（debug 默认）
```

`android/app/android/app/build.gradle.kts` 按 `-PditingAbi` / `--target-platform` 选用
`android/app/android/app/libs/` 下的对应 AAR（可用 `-PtunnelAar=<路径>` 覆盖），缺文件时在配置期
报错。三种 AAR 的架构、压缩与体积、排障见
[`docs/development/aar-build-notes.md`](../docs/development/aar-build-notes.md)。

## Rust 内核（可选）

规则链路有三处 Rust 实现（仓库根 `rust/`）：订阅导入的规则文档解析经 `dart:ffi`，规则写入后的
DTRI 订阅索引编译经 JNI（Kotlin 调用），**域名规则判定内核**由 Go 引擎 `dlopen` 后经 C ABI 调用。
三处都由原实现兜底，且 Go 侧每次应用快照都会把两套判定对拍一遍，不一致就退回 Go。

```bash
python rust/build_android.py        # arm64-v8a + x86_64，两个 .so 拷入 src/main/jniLibs/
python rust/verify.py --all         # fmt / clippy / 单测 / Go 对拍 / Dart 对拍 / 交叉编译 / 基准
```

不生成 `jniLibs/` 里的 `.so` 时行为与以前完全相同（Dart 解析 + Kotlin 索引编译 + Go 判定兜底），
详见 [`rust/README.md`](../rust/README.md)。

## 签名

Release 签名读取 `android/app/android/key.properties` 或 `DITING_KEY*` 环境变量，两者都不入库；
Debug 默认也使用 Release 签名，便于覆盖安装。缺失签名配置时请在打包脚本中选择 Debug 档位。
