# shared/

两个平台共用的 Flutter 包 `diting_shared`：设计系统、主题、本地化、路由/壳层基础，
以及桌面与 Android 都会编译到的旧版配置、SQLite 读取与资源。

```
shared/
├── lib/
│   ├── app/                # 启动引导、主题、l10n 封装
│   ├── l10n/               # ARB 与 gen-l10n 生成文件
│   ├── ui/                 # Material 3 设计系统、组件与图标
│   ├── routes/ shell/      # 两端复用的路由与壳层
│   ├── state/ widgets/     # 共享状态与组件
│   └── data/               # prefs / db / native 桥接等共享读取层
├── assets/                 # 品牌图标、支付码、HTTPS 直通清单
├── shaders/                # liquid_glass.frag
└── tool/                   # i18n 与 UI 取证工具
```

## 边界

- 只放 **两个宿主都需要的代码**。只服务 Android 的页面/原生通道放 `android/app/lib`，
  只服务桌面窗口或 Web 控制台的代码放 `desktop/app/lib`。
- 资源与 shader 通过包 URI 引用，例如
  `packages/diting_shared/assets/images/icon.png`、
  `packages/diting_shared/shaders/liquid_glass.frag`。
- 两端通过 `package:diting_shared/...` 导入，不要反向依赖 `diting_android` 或
  `diting_desktop`。

## 本地化

ARB 与生成文件都在 `lib/l10n`。修改 `app_zh.arb` / `app_en.arb` 后执行：

```bash
cd shared
flutter gen-l10n
```

## 测试

共享包自身没有独立测试入口；两端测试从仓库根运行：

```bash
flutter test android/app
flutter test desktop/app
```
