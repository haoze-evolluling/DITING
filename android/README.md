# android/

谛听（DITING）Android 端专属代码。

```
android/
├── app/                    # Flutter Android 客户端包（lib/、test/、android/ 原生壳）
│   ├── android/            # Gradle / Kotlin / VpnService / 快捷磁贴 / 悬浮窗
│   ├── lib/                # Dart 页面、路由、状态与原生通道
│   ├── test/               # Widget / 单元 / 截图测试
│   └── build_apk.bat       # 交互式 APK 打包
└── engine/                 # Go 隧道引擎源码（gomobile 编译为 AAR）
    └── build_aar.ps1       # 生成 tunnel-arm64 / x64 / all.aar
```

Flutter 工作区根在仓库根 `pubspec.yaml`，共享代码在 `../shared`。

## 常用命令

```bash
# 仓库根：解析整个 Flutter 工作区
flutter pub get
flutter analyze

# Android 测试
cd android/app
flutter test

# 交互式打包（Debug / Release、ARM64 / x86_64、清理缓存）
android\app\build_apk.bat
```

要求 Flutter 3.47+、JDK 11+、Android SDK；最低 Android 9.0（API 28），Release 产物架构为
`arm64-v8a`。

## 隧道引擎 AAR

三种工作模式共用 `engine/` 中的同一套 Go 引擎，差异只在 TUN 路由范围：极速模式仅接管 DNS，
普通模式接管全网络，服务器模式不建隧道。

AAR 是构建产物、不入库。首次打包前在 `android/engine` 执行：

```powershell
pwsh -File build_aar.ps1            # arm64（真机 release）
pwsh -File build_aar.ps1 -Arch x64  # x86_64 模拟器
pwsh -File build_aar.ps1 -Arch all  # 双 ABI（debug 默认）
```

`app/android/app/build.gradle.kts` 会按 `-PditingAbi` / `--target-platform` 自动选用
`app/android/app/libs/` 下的对应 AAR，缺文件时构建报错并提示。详细参数、体积与排障见
[`docs/development/aar-build-notes.md`](../docs/development/aar-build-notes.md)。

## 签名

Release 签名读取 `app/android/key.properties` 或 `DITING_KEY*` 环境变量；两者都不入库。
Debug 默认也使用 Release 签名，便于覆盖安装。缺失签名配置时请在打包脚本中选择 Debug 档位。
