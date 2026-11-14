# 谛听（DITING）Android「自动化能力」扩展调研与设计

> 版本：v0.1　日期：2026-11-14　范围：Android 端自动化 / 场景 / 对外接口　性质：调研 + 可落地方案，不改代码
> 关联：`README.md`、`android/app/android/app/src/main/AndroidManifest.xml`、`rust/diting-subscription-core/src/schedule.rs`、`android/app/lib/state/on_demand_runner.dart`

## 0. 调研方法与核实说明

- 已用 web_fetch 查阅官方文档与开源仓库；`developer.android.com` 直连失败，改用同源镜像 `developer.android.google.cn` 取到页面标题与目录（内容同源，URL 仍按官方域名给出）。
- 已联网核实：Android 各平台页面（快捷设置、App Shortcuts、App Widgets、任务调度/WorkManager、JobScheduler、Alarms、Broadcast、前台服务、深链、NFC、地理围栏、通知、Assistant）、Tasker 插件规范页、MacroDroid Wiki、AdGuard KB（设置页确认「Automation：通过 Tasker 类应用管理 AdGuard」）、sing-box 文档目录（含 Clash API 页）、Surge 手册 HTTP API/Cron/URL Scheme、NextDNS API、Tailscale Exit Nodes、RethinkDNS、Home Assistant Integrations。
- 未能联网核实（标注见文末附录）：Blokada 仓库许可证与细节、Loon 文档、Bixby Routines 第三方 Routines 插件 API、mihomo/Clash.Meta 文档站正文、Google Play 具体审核口径（以发布时政策为准）。

## 1. 结论摘要

1. **现状是「点」不是「面」**：谛听已有快捷磁贴、桌面小组件（三尺寸）、深链 `diting://install-config`、`START/STOP/TOGGLE` 命令、开机自启、按 SSID/蜂窝白名单的按需启动、订阅定时（`schedule.rs` 的 interval/daily/every_other_day）。但缺少统一的**规则引擎**、**定时内核**、**配置档案**、**状态事件出口**，各入口各自为战。
2. **现有命令是 Activity 而非广播**：`QuickActionActivity` 通过 intent-filter 接收三个动作，Tasker「发送意图」可用，但**不能异步返回结果**、成本高、无法做条件/事件插件。建议补一个**签名级权限保护的显式 BroadcastReceiver** + **Tasker/Locale 插件**（编辑页 + FireReceiver + 条件/事件查询）。
3. **最高性价比组合（P0）**：新增 Rust `diting-schedule-core`（复用并泛化 `subscription.schedule`）+ 条件-动作规则引擎 + 配置档案 profiles + 临时暂停 + 状态变更广播与通知快捷动作。这些复用现有 `DataPlaneControl` / `WorkModeNotifier` / `WifiSsidReader` / `VpnChannelWatchdog`，改动面可控。
4. **调度必须双保险**：Kotlin 侧 `AlarmManager.setExactAndAllowWhileIdle` 负责准点，`WorkManager` 周期任务做兜底；当前仓库**明确没有 WorkManager**（`auto_update_runner.dart` 注释「as there is no WorkManager」），订阅自动更新只能在前后台追补，可靠性差。
5. **对外 API 参照成熟范式而非自创**：Surge `/v1` + `X-Key`、Clash `external-controller` + `secret`、sing-box `clash-api`、NextDNS `X-Api-Key`。谛听应做**默认关闭、仅 127.0.0.1、Bearer token、可选 TLS、限流与审计**的本地 HTTP API，并提供 **SSE 事件流 + 出站 Webhook（HMAC 签名）**。
6. **平台面优先级**：动态 App Shortcuts、磁贴长按进设置、Widget 多实例可配置、通知快捷动作 → 高；NFC、地理围栏、前台应用检测 → 低（敏感权限 + 商店政策）。
7. **合规底线**：自动化**不得绕过**首启协议与 VPN 授权（返回 `NeedsApp` 并引导 App）；GPL-3.0 项目可借鉴 GPLv3/MPL/Apache/BSD 代码但须整体 GPL 合规，Surge/Loon 为闭源仅可学思想；精确闹钟在 Android 13+ 对 DNS 类 App 基本只能用 `SCHEDULE_EXACT_ALARM`（用户授权）而非 `USE_EXACT_ALARM`。

## 2. 借鉴表

> 落地难度按「Kotlin / Dart / Rust」三端标注；优先级 P0（近期必做）/ P1（下一阶段）/ P2（储备）。

| 项目 / 平台 | 许可证或文档 | 机制 | 对谛听设计 | 落地难度 | 优先级 | 参考 URL |
|---|---|---|---|---|---|---|
| Android 快捷设置磁贴 | 官方文档 | TileService + `TOGGLEABLE_TILE` + `startActivityAndCollapse` + 长按进设置 | 已有 `DitingTileService`；补长按进「自动化/磁贴设置」页、多状态副标题 | Kotlin | P0 | https://developer.android.com/develop/ui/views/quicksettings-tiles |
| Android App Shortcuts（静态/动态） | 官方文档 | `shortcuts.xml` 静态 ≤5 项；`ShortcutManagerCompat.pushDynamicShortcut` 动态 | 启动/停止/切换模式/临时暂停/最近档案 | Kotlin + Dart | P0 | https://developer.android.com/develop/ui/views/launch/shortcuts |
| Android App Widgets | 官方文档 | AppWidgetProvider + `android:configure` 配置 Activity + 多实例 id | 现有三尺寸 Widget 扩为「按实例绑定档案/指标」 | Kotlin + Dart | P0 | https://developer.android.com/develop/ui/views/appwidgets/overview |
| Android WorkManager / 任务调度 | 官方文档 | 周期/一次性约束任务、可 deferrable、跨重启 | 定时内核兜底、订阅自动更新后台化、低电量/充电约束动作 | Kotlin | P0 | https://developer.android.com/develop/background-work/background-tasks/persistent |
| Android JobScheduler | 官方文档 | `JobInfo` 约束（充电/网络/空闲）+ 周期 | WorkManager 不便时的替代；与 WorkManager 二选一 | Kotlin | P1 | https://developer.android.com/reference/android/app/job/JobScheduler |
| Android AlarmManager（精确闹钟） | 官方文档 | `setExactAndAllowWhileIdle`、`SCHEDULE_EXACT_ALARM` | 分时启停/分时拦截的准点触发；Doze 下妥协策略 | Kotlin | P0 | https://developer.android.com/develop/background-work/services/alarms |
| Android Broadcasts | 官方文档 | 显式/隐式广播、`goAsync`、权限保护 | 新增签名权限 `CONTROL` 的 `AutomationReceiver`；状态变更事件广播 | Kotlin | P0 | https://developer.android.com/develop/background-work/background-tasks/broadcasts |
| Android 前台服务 | 官方文档 | `foregroundServiceType`、Android 12+ 后台启动限制 | 复用现有 `specialUse`；后台自动化执行需 FGS 或转前台 | Kotlin | P0 | https://developer.android.com/develop/background-work/services/fgs |
| Android 深链 / App Links | 官方文档 | `diting://` scheme；`https` verified App Links | 保留 `diting://`；新增 `diting://automation?...`、`diting://profile/...` | Kotlin + Dart | P1 | https://developer.android.com/training/app-links |
| Android 通知与快捷动作 | 官方文档 | 通知 action `PendingIntent`、通道 | 运行通知加「停止 / 暂停 1 小时 / 切换档案」 | Kotlin | P0 | https://developer.android.com/develop/ui/views/notifications/build-notification |
| Android NFC | 官方文档 | `NfcAdapter`、NDEF、前台分发 | 贴标签触发档案/模式切换（低频，P2） | Kotlin | P2 | https://developer.android.com/develop/connectivity/nfc/nfc |
| Android 地理围栏 | 官方文档 | `GeofencingClient` + `ACCESS_BACKGROUND_LOCATION` | 到家/到公司自动切档案（敏感权限，P2） | Kotlin | P2 | https://developer.android.com/develop/sensors-and-location/location/geofencing |
| Google Assistant for Android / App Actions | 官方文档 | `shortcuts.xml` capability、内置 intent `OPEN_APP_FEATURE` | 语音「打开谛听启动/切换」 | Kotlin + XML | P2 | https://developer.android.com/develop/devices/assistant/overview |
| Tasker 插件协议 | 官方开发者页 | `TaskerPlugin.java`、EditActivity/FireReceiver/Condition/Event、同步返回变量 | 谛听做 Action/Condition/Event 三类插件；MacroDroid 也走 Locale 协议 | Kotlin | P1 | https://tasker.joaoapps.com/plugins.html |
| Locale/Tasker 基础规范 | twofortyfouram 规范 | `FIRE_SETTING`/`EDIT_SETTING`/`QUERY_CONDITION`/`REQUEST_QUERY` | 按规范自实现，避免直接拷贝 Tasker 源码的许可纠葛 | Kotlin | P1 | http://www.twofortyfouram.com/developer.html |
| MacroDroid | 官方 Wiki | 触发器/动作/约束、Webhooks、Geofences、Modes、Tasker/Locale 插件 | 通过插件 + 「发送意图」双通道；其 Webhook 思路可借鉴出站事件 | Kotlin | P1 | https://wiki.macrodroid.com/wiki/ |
| AdGuard for Android（自动化） | GPL-3.0（建议核对仓库 LICENSE） | 设置 → 高级 → Automation（通过 Tasker 类应用管理）；Intent 控制 | 自动化开关放「设置 → 高级」；用 intent 即可被 Tasker 管理 | Kotlin | P1 | https://adguard.com/kb/adguard-for-android/features/settings/ |
| RethinkDNS（rethink-app） | MPL-2.0（建议核对） | 本地 DNS+防火墙、按应用/网络规则、always-on | 规则与网络条件模型参考；MPL 与 GPL 兼容 | Dart/Rust | P1 | https://rethinkdns.com/ ；https://docs.rethinkdns.com/ |
| Blokada | 需核对（未能联网核实） | 本地 VPN 拦截、组/规则切换、自动化 | 规则分组切换的产品化参考 | — | P2 | https://blokada.org/ |
| Tailscale（Exit node / profiles） | BSD-3-Clause | exit node 选择、profile/账号切换、`tailscale up --exit-node` | 「档案」与「出口/上游切换」交互参考 | Kotlin/Dart | P2 | https://tailscale.com/docs/features/exit-nodes |
| sing-box Clash API | GPL-3.0（建议核对） | `experimental.clash-api` 本地控制接口 + secret | 本地 HTTP API 端点与鉴权范式 | Rust/Kotlin | P1 | https://sing-box.sagernet.org/configuration/experimental/clash-api/ |
| Clash / mihomo external-controller | GPL-3.0（未能联网核实正文） | `external-controller: 127.0.0.1:9090` + `secret`，REST 控制 | 与 Surge 二选一作 API 蓝本；`/proxies`/`/configs` 语义 | Rust/Kotlin | P1 | https://github.com/MetaCubeX/mihomo |
| Surge（iOS/Mac） | 闭源，仅手册 | `http-api = key@host:port`、`X-Key`、`/v1/*`、cron 脚本、URL Scheme | **最佳 API 蓝本**：GET/POST + JSON、事件、profile switch | Kotlin/Rust | P0 | https://manual.nssurge.com/tools/http-api.html |
| Surge Cron Script | 闭源，仅手册 | `cronexp="0 2 * * *"`、`wake-system` 唤醒、手动触发 | 定时内核的 cron 语义与「设备休眠漏跑」提示 | Rust | P0 | https://manual.nssurge.com/scripting/cron.html |
| Surge URL Scheme | 闭源，仅手册 | `surge:///start|stop|toggle|install-config?url=` | 谛听 `diting://` 已同型，补 `toggle`/`profile` | Kotlin/Dart | P0 | https://manual.nssurge.com/tools/url-scheme.html |
| NextDNS API | 商业服务，ToS 限制 | `X-Api-Key`、profiles/analytics/logs、SSE 日志流 | profile 概念、日志事件流、鉴权方式参考（勿照搬数据模型） | Rust/Dart | P2 | https://nextdns.github.io/api/ |
| Home Assistant | 官方文档 | 集成 + Webhook 触发器 + REST/事件 | 出站 Webhook 的标准接收端示例；可选 HA 集成思路 | — | P2 | https://www.home-assistant.io/integrations/ |

## 3. 建议的「自动化 / 场景」整体架构

### 3.1 现状盘点与差距

| 能力 | 现有实现 | 缺口 |
|---|---|---|
| 启停 / 切换 | `QuickActionActivity`（Activity + intent-filter，导出）、`DataPlaneControl`、`VpnBridge` | 无广播入口、无返回值、无 Tasker 插件 |
| 磁贴 / 组件 | `DitingTileService`、`DitingWidgetProvider`（三尺寸）、`DitingWidgetToggleReceiver`（非导出） | 磁贴长按无设置页；组件不可按实例配置 |
| 深链 | `diting://install-config`、`diting://install-sub`（`DeepLinkBridge`） | 无 `diting://automation`、无 App Links |
| 定时 | `diting-subscription-core/src/schedule.rs`（interval / daily / every_other_day） | 仅订阅更新；无 cron、无窗口、无通用定时内核 |
| 网络条件 | `OnDemandRunner`（Dart 侧 SSID 白名单）、`VpnChannelWatchdog`（`ConnectivityManager.NetworkCallback`） | 仅按需启动；未做通用「网络变化触发动作」 |
| 后台可靠性 | 前台追补（`auto_update_runner.dart`，无 WorkManager） | 无周期任务、无重启后补跑 |
| 事件出口 | 无 | 无状态广播 / Webhook / 本地 API |
| 配置档案 | 无（仅订阅分组） | 无多套配置、无随场景自动切换 |

#### 3.1.1 现有代码锚点（实现落点）

| 新增/改造点 | 复用或落点文件 | 处理方式 |
|---|---|---|
| 启停/切换复用 | `android/.../control/DataPlaneControl.kt` | 规则动作直接调 `start/stop/toggle` |
| 工作模式切换 | `android/app/lib/state/work_mode_providers.dart`（`WorkModeNotifier`） | `mode.set` 动作调用 `select` |
| 网络变化触发 | `.../watchdog/VpnChannelWatchdog.kt`（`NetworkCallback`） | 抽公共回调分发到 `AutomationEngine` |
| SSID 条件 | `.../platform/WifiSsidReader.kt` | 条件求值复用 |
| 深链解析 | `.../deeplink/DeepLinkBridge.kt` | 增 `automation` / `profile` host |
| 磁贴 | `.../tile/DitingTileService.kt` | 长按入口已具备，补 `updateTileState` 显示档案 |
| 组件 | `.../widget/DitingWidgetProvider.kt` + `res/xml/diting_widget_info.xml` | 加 `android:configure` 与 per-id 配置 |
| 通知 | `.../normal/VpnNotification.kt`、`.../platform/NotificationNative.kt` | 加 action `PendingIntent` |
| 订阅定时复用 | `rust/diting-subscription-core/src/schedule.rs` | 抽 `Cadence`，新 crate 依赖 |
| 内核合并 | `rust/diting-kernels/src/lib.rs`、`rust/build_android.py` | 追加 `pub use` 与依赖 |
| FFI 缺库硬错模式 | `android/app/lib/state/backup_providers.dart` 的 `RustBackupCore.instance` | 仿写 `RustScheduleCore.instance` |
| 规则开关 | `rust/diting-rule-store-core`、`VpnBridge.reloadRules` | `rule.group.enable` 动作后热重载 |

### 3.2 总体分层

```
┌──────────────────────────── Flutter (Dart) ─────────────────────────────┐
│ 自动化页：规则编辑 / 档案 / 分时表 / 审计时间线                             │
│ 存储：SharedPreferences(轻量) + SQLite(规则/档案/历史)                     │
│ 通道：MethodChannel com.haoze.diting/automation                          │
└───────────────┬──────────────────────────────────────────────────────────┘
                │ JSON（构造本地 day→slot 表、下发规则、接收事件）
┌───────────────▼────────────── Kotlin（平台能力） ────────────────────────┐
│ AutomationEngine（规则评估/冲突/冷却）  ScheduleController（Alarm+WorkManager）│
│ AutomationReceiver（签名权限）  TaskerPlugin（Edit/Fire/Condition/Event）   │
│ Shortcuts / Tile / Widget(config) / Notification / NFC / Geofence          │
│ DataPlaneControl ─ VpnChannelWatchdog ─ WorkModeNotifier ─ 现有三种服务     │
└───────────────┬──────────────────────────────────────────────────────────┘
                │ FFI（JSON 进出，和现有 *-core 一致）
┌───────────────▼──────────────── Rust kernels ────────────────────────────┐
│ diting-schedule-core（cron/interval/daily/window/pause 求值）              │
│ diting-subscription-core::schedule（复用/抽取公共 Cadence）                 │
│ diting-policy-core / diting-dns-config-core / diting-rule-store-core（动作落地）│
└──────────────────────────────────────────────────────────────────────────┘
```

### 3.3 条件-动作（Condition-Action）模型

一条规则的声明式结构（存 SQLite，JSON 同步给 Kotlin/Rust）：

```json
{
  "id": "auto_001",
  "name": "到家关闭拦截并切换家庭档案",
  "enabled": true,
  "priority": 100,
  "match": "all",
  "triggers": [
    { "type": "schedule", "cadence": "daily", "time": "18:30", "days": [1,2,3,4,5] },
    { "type": "network", "on": ["wifi"] }
  ],
  "conditions": [
    { "type": "ssid", "in": ["Home-5G"] },
    { "type": "battery", "min": 20 },
    { "type": "vpnState", "in": ["running", "stopped"] }
  ],
  "actions": [
    { "type": "profile.activate", "profile": "home" },
    { "type": "rule.group.disable", "group": "adult" },
    { "type": "notify", "title": "谛听", "text": "已切换到家庭档案" }
  ],
  "cooldownSec": 300,
  "windowSec": 600,
  "once": false
}
```

**评估语义（必须固化，避免「玄学自动化」）**：
- **触发去抖**：网络/前台应用类触发 1–2s 去抖；同一规则在 `cooldownSec` 内不重复执行。
- **优先级与冲突**：`priority` 高者覆盖低者；「手动动作」写入 `overrideUntil`，在窗口内不被规则覆盖（借鉴 `OnDemandRunner` 的「网络未变不覆盖手动」思路）。
- **幂等优先**：规则内优先用 `start/stop`/`profile.activate` 等「目标态」动作，避免 `toggle` 造成抖动。
- **补跑策略**：定时触发以 `lastRunAt` 判定，`windowSec` 内补跑一次，超出则合并为一次（避免睡醒后连爆）。
- **失败可解释**：需要用户参与的（未同意协议 / 无 VPN 授权 / 无启动配置）返回 `NeedsApp`，发通知并高亮页面，不静默失败。
- **安全不可绕过**：任何自动化动作都先过 `DataPlaneControl.isAgreementAccepted()` 与 `VpnService.prepare()` 检查。

#### 3.3.1 触发器（Trigger）

| 类型 | 来源 | 说明 |
|---|---|---|
| `app.start` / `boot` / `package.replaced` | 现有 `DnsModeBootReceiver` 可扩展 | 开机/更新后恢复自动化 |
| `network.changed` | `VpnChannelWatchdog` 的 `NetworkCallback` | Wi-Fi/蜂窝切换、SSID 变化 |
| `vpn.state` | 三个 Service 的 `isRunning` 状态回调 | 启动/停止/异常 |
| `schedule.tick` | `diting-schedule-core` + `ScheduleController` | cron / 定时 / 窗口 |
| `screen.on/off`、`charging`、`battery` | `BroadcastReceiver`（`ACTION_SCREEN_ON` 等） | 低功耗场景 |
| `foreground.app` | `UsageStatsManager`（特殊权限） | P2，敏感 |
| `geofence.enter/exit` | `GeofencingClient`（后台定位权限） | P2，敏感 |
| `nfc.tag` | `NfcAdapter` 前台分发 | P2 |
| `manual` / `api` / `tasker` | 广播 / HTTP / 插件 | 外部驱动 |

#### 3.3.2 条件（Condition）

| 条件 | 实现来源 | 备注 |
|---|---|---|
| 网络类型（wifi/cellular/ethernet/vpn） | `ConnectivityManager`（`NetInfoProbe` 已有读取） | 无需新权限 |
| SSID | `WifiSsidReader`（已有，需定位/NEARBY_WIFI_DEVICES） | 复用现有实现 |
| 时间/星期/时间窗口 | Dart 本地 `DateTime` 构造 day→slot（同 `schedule.rs` 注入法） | 时区/DST 由 Dart 负责 |
| 充电/电量 | `BatteryManager` / `ACTION_BATTERY_CHANGED` | 无危险权限 |
| VPN 运行状态/当前模式 | `DataPlaneControl` / `WorkModeNotifier` | 直接读 |
| 当前档案 | 规则引擎状态 | 直接读 |
| 今日拦截数/流量阈值 | `WidgetStats` / `diting-log-query-core` | 可直接查 |
| 前台应用 | `UsageStatsManager` | P2，需「使用情况访问」特殊权限 |
| 地理位置 | `FusedLocationProvider` | P2，需定位权限 |

#### 3.3.3 动作（Action）

| 动作 | 落地实现 | 说明 |
|---|---|---|
| `vpn.start/stop/toggle` | `DataPlaneControl` | 已在磁贴/组件/Activity 共用 |
| `mode.set(normal/express/dns)` | `WorkModeNotifier.select` | 会先停旧服务再切 |
| `profile.activate(id)` | 新增 ProfileManager | 见 3.7 |
| `upstream.select(setId)` | `legacy_settings_dns` 的 provider id 集 + 重启/热重载 | 切换上游服务商集合 |
| `rule.group.enable/disable(id)` | `diting-rule-store-core` + `reloadRules` | 开关某规则库/分组 |
| `feature.set(key,on)` | 缓存/HTTPS 检查/悬浮窗等开关 | 对应现有设置项 |
| `pause.minutes(n)` / `pause.until(ts)` | 暂停**拦截**（引擎旁路，隧道保持） | 与「停止服务」区分，见 3.6 语义 |
| `notify(...)` | `NotificationNative` | 可带快捷动作 |
| `export.backup` / `webhook.post` | `diting-backup-core` / 新 WebhookClient | 导出或上报事件 |

#### 3.3.4 典型场景走查（验证模型是否够用）

1. **到家自动切「家庭档案」并放宽拦截**：触发 `network.changed(wifi)` + `schedule(daily 18:30)`；条件 `ssid in [Home-5G]`、`battery>=20`；动作 `profile.activate(home)`、`rule.group.disable(adult)`、`notify`。命中 `overrideUntil` 时跳过，保留用户手动结果。
2. **会议时段临时暂停**：定时窗口 `window 09:00–18:00 工作日`，动作 `pause.minutes(60)` 在窗口起点执行；窗口结束 `pause.until(windowEnd)` 自动恢复，避免忘记恢复。
3. **游戏加速**：触发 `foreground.app in [game.pkg]`（P2）或手动 Shortcut；动作 `mode.set(express)` + `upstream.select(game)`；退出后 `window` 结束恢复 `normal`。
4. **低电降级**：触发 `battery<threshold` 且 `!charging`；动作 `feature.set(cache=false)`、`notify`；充电后恢复。
5. **Tasker 联动**：外部经插件/广播 `toggle`，谛听回发 `STATE_CHANGED`，Tasker 再控制智能灯（Home Assistant webhook）。

> 走查结论：模型能覆盖启停、模式、档案、规则组、功能开关、暂停、通知、外发；唯独「动作需要用户授权」的情形必须走 `NeedsApp` 回退，因此规则编辑器要对这些动作标注「可能需要手动确认」。

### 3.4 调度内核：新增 Rust crate `diting-schedule-core`

**定位**：把「何时该跑」从业务里剥离成确定性纯函数，供订阅更新与自动化规则共用。无 I/O、`now` 注入、测试可钉住每个边界（与 `schedule.rs` 同纪律）。

**数据模型与 API（草案）**：

```rust
// 输入（JSON，经 FFI 传入；slots 由 Dart 用本地 DateTime 构造）
{
  "nowMs": 1763000000000i64,
  "nowDay": 20600,                 // 本地日序号
  "slots": [{"day":20600,"ms":1763000000000i64}], // 本地时刻→epoch
  "rules": [
    {"id":1,"cadence":{"kind":"cron","expr":"0 2 * * *"},"lastRunAt":0,"windowSec":3600},
    {"id":2,"cadence":{"kind":"daily","time":"04:00","days":[1,2,3,4,5]},"lastRunAt":...},
    {"id":3,"cadence":{"kind":"interval","hours":6},"lastRunAt":...},
    {"id":4,"cadence":{"kind":"window","from":"08:00","to":"23:00","days":[1,2,3,4,5]},"lastRunAt":...},
    {"id":5,"cadence":{"kind":"pause","untilMs":1763003600000i64}}
  ]
}
// 输出：每条规则 {due:bool, nextDueAt:i64|null, windowActive:bool|null}
{ "results":[{"id":1,"due":false,"nextDueAt":1763088000000i64,"windowActive":null}] }
```

**cadence 语义细化**：

| kind | 字段 | 语义 |
|---|---|---|
| `interval` | `hours` | 距 `lastRunAt` 满 N 小时即到期（同现有 interval） |
| `daily` | `time`,`days` | 指定星期/每日的本地时刻；`days` 缺省=每天 |
| `cron` | `expr` | 5 字段子集：`*`、`*/n`、`a,b`、`a-b`；不支持秒级，避免频繁唤醒 |
| `window` | `from`,`to`,`days` | 区间内 `windowActive=true`，边界各产生一次 transition；支持跨天（from>to） |
| `pause` | `untilMs` | 到 `untilMs` 自动清除暂停态并产生一次 restore |

纯函数伪代码（无 I/O，`now` 注入）：

```rust
fn evaluate(now: i64, rules: &[Rule]) -> Vec<Outcome> {
    rules.iter().map(|r| match &r.cadence {
        Cadence::Interval { hours } => due_interval(now, r.last_run_at, *hours),
        Cadence::Daily { .. } | Cadence::Cron { .. } => due_slot(now, r.last_run_at, r),
        Cadence::Window { .. } => window_state(now, r),
        Cadence::Pause { until_ms } => if now >= *until_ms { restore() } else { hold() },
    }).collect()
}
```

**与订阅调度的关系**：把 `schedule.rs` 里的 `Schedule`/`Plan` 抽取为通用 `Cadence`，`subscription-core` 通过 feature 或 crate 依赖复用，避免两份日历逻辑（`schedule.rs` 已证明 interval/daily/every-other-day 的正确性，直接扩展而非重写）。新增 `cron`（5 字段子集：分/时/日/月/周，支持 `*/n`、列表、区间）、`window`（窗口内 active、窗口边界各一个 transition）、`pause`（到某时刻自动恢复）。

**Kotlin `ScheduleController`**：
- 读最短 `nextDueAt` → `AlarmManager.setExactAndAllowWhileIdle`（`canScheduleExactAlarms()` 为真时）；否则退回 `setAndAllowWhileIdle`。
- 同时挂 `WorkManager` 一次性任务作兜底（Doze/厂商杀后台）。
- 监听 `BOOT_COMPLETED`、`ACTION_TIME_CHANGED`、`ACTION_TIMEZONE_CHANGED` 重排；落库 `lastRunAt`。
- 触发后投递 `AutomationReceiver`（显式、签名权限）→ `AutomationEngine.evaluate()`。

**接入方式**：仿 `diting-kernels` 追加依赖并 `pub use diting_schedule_core;`；`build_android.py` 会把它并入 `libditing_kernels.so`；Dart 侧仿 `RustBackupCore.instance` 的「缺库硬报错」模式，不写第二套实现。

### 3.5 平台集成清单

| 机制 | 现状 | 建议 | 优先级 | 权限/限制 |
|---|---|---|---|---|
| Quick Settings Tile | 已有 | 长按 → 自动化/磁贴设置页（已有 `QS_TILE_PREFERENCES` 入口）；副标题显示当前档案 | P0 | 无新权限 |
| App Shortcuts（静态） | 无 | `shortcuts.xml` 4 项：启动/停止、切换模式、临时暂停、打开自动化 | P0 | 无 |
| App Shortcuts（动态） | 无 | 按档案/最近使用 `pushDynamicShortcut` | P0 | 无 |
| App Widget 可配置/多实例 | 部分（多 id、三尺寸） | `android:configure` 配置 Activity，按 `appWidgetId` 存档案与指标 | P0 | 无 |
| 通知快捷动作 | 仅运行通知 | 加「停止 / 暂停 1 小时 / 切换档案」 | P0 | `POST_NOTIFICATIONS` 已有 |
| BroadcastReceiver（对外） | 无（仅 Activity） | 新增 `AutomationReceiver`，签名权限 `CONTROL` | P0 | 自定义签名权限 |
| Tasker 插件 | 无 | EditActivity + FireReceiver + Condition + Event；变量回传状态 | P1 | 遵循 Locale 规范 |
| MacroDroid | 无 | 走插件或「发送意图」 | P1 | 同上 |
| Deep link / App Links | `diting://` | 加 `diting://automation`、`diting://profile/{id}`；评估 `https` App Links | P1 | intent-filter |
| NFC | 无 | 贴标签跑规则（写 tag 映射） | P2 | `NFC` |
| 地理围栏 | 无 | 到家/到公司切档案 | P2 | 后台定位（商店需说明） |
| Bixby Routines / Assistant | 无 | Assistant 用 App Actions；Bixby 深度集成有限 | P2 | 见附录 |
| WorkManager / JobScheduler | 无 | 周期兜底 + 约束动作 | P0 | 无 |
| 前台服务 | 已有 `specialUse` | 后台自动化执行需在 FGS 内或转前台 | P0 | Android 12+ 启动限制 |

### 3.6 对外 API / 事件协议

#### 3.6.1 本地 HTTP API（默认关闭）

参照 Surge `/v1` + `X-Key`、Clash `external-controller` + `secret`、sing-box `clash-api`：

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/v1/status` | `{running, workMode, profileId, blockedToday, version}` |
| POST | `/v1/control` | `{"action":"start|stop|toggle"}` |
| GET/POST | `/v1/mode` | 查询/切换工作模式 |
| GET | `/v1/profiles`　POST `/v1/profiles/activate` | 档案列表 / 激活 |
| GET | `/v1/rules/groups`　POST `/v1/rules/groups/{id}` | 规则分组列表 / 开关 |
| POST | `/v1/pause` | `{"minutes":60}` 或 `{"until":<ms>}` |
| GET | `/v1/stats` | 查询/拦截/缓存统计 |
| GET | `/v1/events` | SSE 状态/事件流 |

**安全边界**：只绑 `127.0.0.1`（默认随机端口，App 内展示；可选固定端口）；`Authorization: Bearer <token>`（32 字节随机，存 `EncryptedSharedPreferences`，亦兼容 `X-Key`）；可选 TLS（复用 MITM CA 自签）；令牌错误限流 + 审计日志；**绝不监听 `0.0.0.0`**，除非用户显式开启并二次确认风险。

#### 3.6.2 事件广播与 Webhook

- **广播**：`com.haoze.diting.action.STATE_CHANGED`，extras `{running, workMode, profileId, blockedToday, reason}`。对内部用显式广播；对第三方用普通自定义权限 `RECEIVE_EVENTS`（Tasker 可申请）。
- **SSE**：`/v1/events` 推送同样结构，便于面板/脚本订阅。
- **出站 Webhook**：仅用户配置的 HTTPS 端点；POST JSON，头带 `X-Diting-Signature: hmac-sha256(body)`；失败指数退避、最多 N 次；payload 最小化（不含查询域名明细，除非用户显式开启）。

#### 3.6.3 Tasker 事件插件

用 Locale 协议实现 Event 插件（`ACTION_EDIT_EVENT` + `QUERY_CONDITION` 返回 `SATISFIED`），事件数据经 `addPassThroughData` 传递；条件插件暴露「是否运行 / 当前模式 / 当前档案 / 今日拦截数>N」。这样 Tasker 用户既能「触发谛听」，也能「被谛听触发」。

**状态事件 payload 示例**：

```json
{
  "event": "state.changed",
  "ts": 1763000000123,
  "running": true,
  "workMode": "normal",
  "profileId": "home",
  "blockedToday": 1284,
  "reason": "profile.activate"
}
```

**Tasker / Locale 关键常量（照规范自实现）**：

| 常量 | 值 | 用途 |
|---|---|---|
| `ACTION_FIRE_SETTING` | `com.twofortyfouram.locale.intent.action.FIRE_SETTING` | 动作插件执行 |
| `ACTION_EDIT_SETTING` | `com.twofortyfouram.locale.intent.action.EDIT_SETTING` | 动作编辑页 |
| `ACTION_QUERY_CONDITION` | `com.twofortyfouram.locale.intent.action.QUERY_CONDITION` | 条件查询 |
| `ACTION_REQUEST_QUERY` | `com.twofortyfouram.locale.intent.action.REQUEST_QUERY` | 事件请求查询 |
| `EXTRA_BUNDLE` | `com.twofortyfouram.locale.intent.extra.BUNDLE` | 参数信封 |
| `EXTRA_STRING_BLURB` | `com.twofortyfouram.locale.intent.extra.BLURB` | 一行摘要 |

> 同步返回变量：`onReceive` 内 `isOrderedBroadcast()` 为真时 `setResultCode(RESULT_CODE_OK)`；耗时则先返回 `RESULT_CODE_PENDING`，Service 完成后 `TaskerPlugin.Setting.signalFinish(...)`。

### 3.7 配置档案（Profiles）

- **模型**：`profile = {id, name, workMode, upstreamSetId, ruleGroupStates, featureToggles, outboundProxy, notes}`，即一份配置快照。
- **切换**：`ProfileManager.activate(id)` →（如需）停服务 → 写入设置 → 依当前模式重启或热重载规则。
- **自动切换**：档案可绑定触发（SSID/时间/地理），由规则引擎驱动；冲突按 3.3 优先级。
- **导入导出/分享**：复用 `diting-backup-core` 的分组信封，导出 `.ditingprofile`；注意剔除密钥类字段（代理密码/订阅 token）或显式提醒。

### 3.8 权限与安全

- **新增权限**：`SCHEDULE_EXACT_ALARM`（精确闹钟，用户可授）、`RECEIVE_BOOT_COMPLETED`（已有）、`NFC`（P2）、`ACCESS_BACKGROUND_LOCATION`（P2，商店需说明）、自定义签名权限 `com.haoze.diting.permission.CONTROL`。
- **不新增**：`USE_EXACT_ALARM`（Android 13+ 仅闹钟/日历类可用，DNS 工具不应申请）、无障碍服务（严禁）、`QUERY_ALL_PACKAGES` 保持现状并在商店声明。
- **命令入口分级**：Activity（兼容旧 Tasker）→ 广播（签名权限）→ 插件（Locale 协议）→ HTTP（token）。adb 可向导出组件发意图，但受权限约束；HTTP 另有 token。
- **数据最小化**：Webhook/SSE 默认不含域名级明细；审计日志本地保留可清理（复用现有 `diting-cleanup-core`）。
- **降级**：后台起 FGS 被拒（Android 12+）时，沿用现有「打开 App」回退（`DataPlaneControl.startForeground` 已处理），并提示用户授权「忽略电池优化」。

### 3.9 分阶段实施路线

- **P0（1 个迭代）**：`diting-schedule-core` + 规则引擎骨架 + 配置档案 + 临时暂停 + 状态广播 + 通知动作 + 动态 Shortcuts + Widget 多实例配置 + 引入 WorkManager。
- **P1（2–3 个迭代）**：Tasker 插件（动作/条件/事件）+ AutomationReceiver + 本地 HTTP API + Webhook + 分时拦截可视化编辑 + 自动化审计时间线。
- **P2（储备）**：NFC、地理围栏、前台应用触发、Home Assistant 集成、Assistant App Actions 深化、自动化配置分享。

### 3.10 数据模型（SQLite 草案）

复用现有 `diting_database`，新增三表（避免与日志表混写）：

```sql
CREATE TABLE automation_rule (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, enabled INTEGER NOT NULL,
  priority INTEGER NOT NULL DEFAULT 100, match TEXT NOT NULL DEFAULT 'all',
  spec_json TEXT NOT NULL,          -- triggers/conditions/actions/cooldown/window/once
  last_run_at INTEGER NOT NULL DEFAULT 0,
  cooldown_sec INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
);
CREATE TABLE automation_profile (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  payload_json TEXT NOT NULL,       -- workMode/upstreamSet/ruleGroups/featureToggles
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
);
CREATE TABLE automation_event (     -- 审计时间线，按 retention 清理
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL, rule_id TEXT, event TEXT NOT NULL,
  outcome TEXT, detail_json TEXT
);
```

> 与现有 `diting-cleanup-core` 的清理目录对齐，避免 `automation_event` 无限增长；规则/档案建议纳入 `diting-backup-core` 的备份分组。

### 3.11 关键风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 精确闹钟 / Doze 漏跑 | 分时启停不准 | Alarm + WorkManager 双保险，UI 明示「可能延迟」 |
| 厂商杀后台 | 定时/事件不触发 | 引导「忽略电池优化」，FGS 兜底 |
| 后台起 FGS 被拒（Android 12+） | 动作失败 | 沿用 `NeedsApp` 打开 App 回退 |
| 规则冲突 / 抖动 | 服务反复启停 | 冷却 / 优先级 / 幂等目标态 / 去抖 |
| 导出配置泄露密钥 | 隐私 | 导出剔除 token/密码，或加密并要求口令 |
| 对外入口被滥用 | 被第三方控制 VPN | 签名权限 + token + 默认关闭 + 审计 |

## 4. 新功能清单（归入「自动化能力」）

### P0

| 编号 | 功能 | 价值 | 方案（Kotlin/Dart/Rust） | 风险 |
|---|---|---|---|---|
| A1 | 条件-动作规则引擎 | 把零散入口统一为「规则」，用户可组合场景 | Kotlin `AutomationEngine` 评估；Dart 编辑器/存储；Rust 纯函数判定 | 规则冲突/抖动需冷却与优先级；调试成本高 |
| A2 | `diting-schedule-core` 定时内核 | 分时启停、分时拦截、订阅更新的统一「准点」 | Rust 新 crate 复用 `schedule.rs`；Kotlin Alarm+WorkManager 协同 | 精确闹钟授权被拒/Doze 漏跑；厂商杀后台 |
| A3 | 配置档案 Profiles | 多套配置一键切换；随场景自动切换 | Dart `ProfileManager`；Kotlin 应用/重启；复用备份信封 | 切换需停/起服务，可能瞬断；密钥导出泄露 |
| A4 | 临时暂停 | 「看视频/下载时暂停拦截」，比停服务更轻 | 引擎旁路标志（拦截跳过、DNS 仍走）；通知倒计时 | 需引擎侧支持旁路；用户误解为「已停止」 |
| A5 | 状态变更广播 + 通知快捷动作 | 外部可观测、可联动；通知里直接控制 | Kotlin 发显式广播 + 通知 action `PendingIntent` | 广播被滥用 → 签名权限；通知权限缺失 |
| A6 | Widget 多实例可配置 + 动态 Shortcuts | 一屏多档案/多指标；长按直达常用动作 | Kotlin `android:configure` + `pushDynamicShortcut`；Dart 配置 UI | 配置状态需随卸载清理；入口过多易混乱 |
| A7 | 引入 WorkManager 后台调度 | 修复「无 WorkManager」导致的自动更新不可靠 | Kotlin `WorkManager` + 现有 Dart 追补逻辑合并 | 周期下限 15 分钟；与省电策略冲突 |

### P1

| 编号 | 功能 | 价值 | 方案（Kotlin/Dart/Rust） | 风险 |
|---|---|---|---|---|
| B1 | Tasker/Locale 插件（动作+条件+事件） | Tasker/MacroDroid 生态直接接入，双向联动 | Kotlin EditActivity/FireReceiver/Query；`TaskerPlugin` 兼容 | 插件协议细节多；需同步返回变量处理超时 |
| B2 | 签名权限 `AutomationReceiver` 广播入口 | 比 Activity 轻、可后台、可 adb | Kotlin `BroadcastReceiver` + `goAsync` | 误配导出/权限导致被他人控制 |
| B3 | 本地 HTTP API（localhost + token） | 面板/脚本/HA 可远程控制与观测 | Kotlin 轻量 HTTP（`NanoHTTPD` 或自实现）；Rust 提供序列化 | 端口/token 泄露；商店对「服务器」敏感 |
| B4 | 出站 Webhook（HMAC） | 与 HA/n8n/自建服务联动 | Kotlin `OkHttp`/`HttpURLConnection`；Dart 配置 | SSRF/重试风暴；隐私外泄需明示 |
| B5 | 分时拦截（timetable 可视化） | 学习/工作时段自动收紧或放宽规则 | Dart 周视图编辑器；Rust window 求值 | 跨天窗口/DST 边界易错 |
| B6 | 上游/规则分组随场景切换 | 「游戏加速」「办公去广告」等一键切换 | 复用 provider id 集 + `reloadRules`；Dart 场景绑定 | 切换需重建引擎，注意瞬断与回滚 |
| B7 | 自动化审计时间线 | 排障与信任（什么时候、为何触发） | Kotlin 事件表（复用 log 表）；Dart 展示 | 日志增长；敏感信息脱敏 |

### P2

| 编号 | 功能 | 价值 | 方案（Kotlin/Dart/Rust） | 风险 |
|---|---|---|---|---|
| C1 | NFC 标签触发 | 贴标签切档案/模式，离线可靠 | Kotlin `NfcAdapter` 前台分发 + tag→规则映射 | 需 NFC 硬件；标签可被复制 |
| C2 | 地理围栏（到家/到公司） | 真正「场景化」自动切换 | Kotlin `GeofencingClient` + 后台定位 | 后台定位商店政策；耗电 |
| C3 | 前台应用触发 | 「打开某 App 自动开启」 | Kotlin `UsageStatsManager` | 特殊权限；隐私敏感 |
| C4 | 电量/充电/屏幕状态触发 | 低电停拦截、充电时更新 | Kotlin 系统广播 | 触发频繁需去抖 |
| C5 | Home Assistant 集成 | 智能家居联动 | 出站 Webhook + REST 轮询；文档给示例 | 需用户自建服务 |
| C6 | Assistant App Actions / Bixby | 语音控制 | `shortcuts.xml` capability + `OPEN_APP_FEATURE` | Bixby 深度集成受限；见附录 |
| C7 | 自动化配置分享（`.ditingauto`） | 社区传播场景模板 | Dart 导出/导入 + 校验；Rust 校验 | 导入不可信配置需签名/校验 |

### 交付验收标准（自动化能力）

- 规则 CRUD 与导入导出可用；单条规则可「测试运行」并显示命中/未命中原因。
- 定时内核：interval/daily/cron/window/pause 各有单测，钉住时区与 DST 边界；与 `subscription.schedule` 共用 `Cadence` 且无回归。
- 外部控制：Tasker 动作/条件/事件、广播、HTTP `/v1/control` 三通道均能启停并回读状态；未授权请求被拒并留审计。
- 可靠性：重启后规则恢复；Doze 下漏跑在 `windowSec` 内补跑一次。
- 安全：签名权限缺失的第三方无法触发；HTTP 仅 127.0.0.1；自动化不能绕过首启协议与 VPN 授权。

## 5. 许可证 / 合规提示

**GPL-3.0 基线**：谛听为 GPL-3.0。可借鉴/引入 **GPLv3、MPL-2.0、Apache-2.0、BSD、MIT** 代码（保持整体 GPLv3 并保留版权与许可声明）；**不可**引入 GPL-2.0-only、闭源或与 GPL 不兼容的代码。

| 参考对象 | 许可证（状态） | 使用建议 |
|---|---|---|
| AdGuard for Android | GPL-3.0（已核对其文档站，仓库 LICENSE 建议再核对） | 可借鉴实现；若拷贝需保留版权并整体 GPLv3 |
| RethinkDNS（rethink-app） | MPL-2.0（建议核对仓库） | 与 GPL 兼容；文件级 copyleft，改其文件需回馈该文件 |
| Blokada | 未能联网核实 | 使用前必须核对 LICENSE |
| sing-box | GPL-3.0（建议核对） | 兼容；整包派生需开源 |
| mihomo / Clash.Meta | GPL-3.0（未能联网核实正文） | 同上 |
| Surge / Loon | 闭源专有，仅公开手册 | **只学思想与接口形状，不拷贝代码/资源** |
| Tasker / Locale 插件源码 | Tasker 发布 `TaskerPlugin.java`（遵循 twofortyfouram 规范，Apache-2.0 字样需核对） | 建议**按规范自实现**，避免直接拷贝带来的许可与商标纠葛 |
| Tailscale | BSD-3-Clause | 兼容，保留声明 |
| NextDNS API | 商业服务 ToS | 仅参考接口形状，勿照搬其数据模型或依赖其服务 |

**Google Play 政策要点（发布前以最新政策为准）**：
- `QUERY_ALL_PACKAGES` 需在商店声明用途（现有已用）。
- 后台定位（地理围栏）需 `ACCESS_BACKGROUND_LOCATION` + 政策声明与合理用途。
- 精确闹钟：DNS 工具通常**不能**申请 `USE_EXACT_ALARM`，只能 `SCHEDULE_EXACT_ALARM`（用户授权）或退化为非精确；切勿为「准点」强求豁免。
- 避免无障碍服务、避免读取通知内容；「前台应用」用 `UsageStatsManager` 而非无障碍。
- VPN 服务政策：谛听本身即 VPN 类应用，需透明的隐私说明；自动化不得在用户不知情下开启隧道。

**隐私**：Webhook/SSE/HTTP API 默认不含域名级明细；所有对外数据需显式开启并告知；自动化配置导出默认剔除密钥类字段。

**来源记录规范**：每引入一段外部实现，在 `docs/planning/research/` 增加一条来源（项目、版本、LICENSE、URL、改动摘要），并在文件头保留原始版权与 SPDX 标识；GPLv3 派生文件随仓库整体开源，MPL 文件保持文件级许可声明。

## 附录：核实状态与参考链接

- 已核实（官方/同源镜像）：`developer.android.com` 各条目（快捷设置、Shortcuts、AppWidgets、任务调度、JobScheduler、Alarms、Broadcast、FGS、深链、NFC、地理围栏、通知、Assistant）；`tasker.joaoapps.com/plugins.html`；`wiki.macrodroid.com`；`adguard.com/kb/adguard-for-android/features/settings/`（确认 Automation 经 Tasker 类应用）；`sing-box.sagernet.org`（目录含 Clash API）；`manual.nssurge.com`（HTTP API / Cron / URL Scheme）；`nextdns.github.io/api/`；`tailscale.com/docs/features/exit-nodes`；`rethinkdns.com`；`home-assistant.io/integrations`。
- 未能联网核实：Blokada 许可证与自动化细节、Loon 文档、Bixby Routines 第三方插件 API、mihomo/MetaCubeX Wiki 正文、Google Play 具体审核口径。
- 建议在实现前对 `AdGuard / sing-box / mihomo / Blokada` 的仓库 `LICENSE` 逐一复核，并在 `docs/` 留下来源与版权记录。
