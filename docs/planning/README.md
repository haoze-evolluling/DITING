# 谛听（DITING）安卓端功能扩展规划

> 本目录是**规划文档集**，不含代码改动。目标：结合现有 Flutter 架构与 Rust 内核、借鉴优秀开源项目的设计与机制，
> 围绕 **网络管理 · 规则管理 · 自动化能力 · 整体使用体验** 四条主线，挖掘值得引入的新功能，并给出优先级与可落地方案。
> 基线版本：安卓 **2.4.2+20402**；协议：**GPL-3.0**。

## 文档导航

| 文档 | 内容 |
|---|---|
| [01-现状与架构分析](01-现状与架构分析.md) | 产品定位、Flutter 分层、49 个 Rust 内核全景（引擎/内核/桌面三组）、现状能力矩阵、桌面↔安卓差集、扩展红线 |
| [02-开源借鉴与设计机制](02-开源借鉴与设计机制.md) | 四方向调研汇总：借鉴总览表、关键机制提炼、许可证矩阵、“不建议引入”清单 |
| [03-功能扩展清单与优先级](03-功能扩展清单与优先级.md) | 逐条功能（N/R/A/U/K 五组，含价值/方案/规模/优先级/依赖）、优先级分布、Top 10 快速见效 |
| [04-路线图与落地方案](04-路线图与落地方案.md) | 四阶段路线图与版本建议、Rust/Flutter/Kotlin 改造清单、数据模型、配置文档、测试、风险、人力估算 |
| [research/network.md](research/network.md) | 原始调研：网络管理（sing-box/NetGuard/RethinkDNS/Clash/PCAPdroid 等） |
| [research/rules.md](research/rules.md) | 原始调研：规则管理（AdGuard/AdGuard Home/FiltersCompiler/sing-box/blocky 等） |
| [research/automation.md](research/automation.md) | 原始调研：自动化（Surge/Clash API/Tasker/MacroDroid/Android 平台） |
| [research/ux-kernel.md](research/ux-kernel.md) | 原始调研：体验与 Rust 内核 leverage（AdGuard/RethinkDNS/FlClash/M3） |

## 核心结论（一页速览）

1. **谛听的功能面已经很宽**，真正的缺口不是“再加一个入口”，而是**可信（可解释）、可编排（自动化）、可观测（可视化）、
   可维护（治理与健康）**。扩展应围绕这四点做“横向能力”，而非平铺功能。
2. **最大的“内核杠杆”**：桌面端已成熟的 `diting-safebrowsing-core`、`diting-dns64-core`、`diting-ratelimit-core`、
   `diting-filter-core`、`diting-rewrite-core`、`diting-stamp-core` **尚未链接进安卓引擎**；它们可作为普通 Rust 依赖
   静态并入 `libditing_engine.so`，以极低成本补齐隐私套件、IPv6-only（DNS64）、LAN 限速等能力。
3. **投入产出比最高的“低垂果实”**（桌面已有、安卓可快速补齐）：
   - **规则测试模拟器**（复用 `policy-core` 判定，桌面 `/filter/check` 同型）；
   - **规则命中统计 + “为什么被拦截”归因**（AdGuard Home `Result.rules[]` 模型）；
   - **临时暂停拦截 / 仅白名单模式**（引擎旁路）；
   - **订阅库健康状态**（ok/304/cached/failed）。
4. **自动化要从“三个命令”升级为“条件-动作场景引擎”**：新增 `diting-schedule-core`（抽 `subscription.schedule` 的
   `Cadence`，扩 cron/window/pause）+ 规则引擎（触发/条件/动作/冷却/优先级/幂等/补跑）+ 配置档案 Profiles +
   状态广播 / Tasker 插件 / 本地 HTTP API / Webhook 四类出口；补 `WorkManager` 后台可靠性。
5. **网络管理要“从能跑到可编排”**：网络 Profile（按 Wi-Fi/蜂窝/漫游/计费差异化）、条件路由（`policy-core` 决策第二输出：
   上游/出口/回退链）、策略组与回退链、实时 Flow 连接视图、Kill switch、DNS 泄漏检测与 Captive Portal。
6. **体验层补四件事**：**保护健康评分 + Advisor**（权限/DNS/过滤器/缓存/拦截 → 下一步建议）、**全局搜索/命令面板**、
   **应用报告卡/连接地图**、**a11y/i18n/自适应**；视觉沿用 `diting_shared/ui`，走渐进披露。

## 路线图一览（详见 04）

| 阶段 | 版本（建议） | 主题 | 代表功能 |
|---|---|---|---|
| 0 · 地基 | 2.5.0 | 底座 | schedule-core、命中计数内核、WorkManager、状态广播、ABI/配置规范 |
| 1 · 可解释与轻控制 | 2.6.0 | 可信可用 | 规则测试、命中统计+归因、订阅健康、临时暂停/仅白名单、Flow 视图、健康顾问、全局搜索 |
| 2 · 场景与策略 | 2.7.0 | 自动化+路由 | 条件-动作引擎、Profiles、网络 Profile、条件路由、策略组、分时规则、Tasker 插件 |
| 3 · 纵深与生态 | 3.0.0 | 隐私+协议+生态 | safebrowsing/dns64/ratelimit 并入、隐私套件、DoH3、DNS64、LAN 限速、HTTP API/Webhook、a11y/i18n/自适应 |

## Top 10 快速见效（建议首迭代）

1. 规则测试模拟器（R1） 2. 规则命中统计+归因（R2） 3. 订阅健康状态（R3） 4. 临时暂停+仅白名单（R4）
5. 实时连接视图（N4） 6. 保护健康评分+Advisor（U1） 7. 全局搜索/命令面板（U2）
8. 状态广播+通知动作+WorkManager（A5/A7） 9. 配置档案 Profiles（A3） 10. 接入 safebrowsing+dns64（K1）

## 调研方法与可信度

- 已联网核实：sing-box、AdGuard（语法/统计/自动化）、AdGuard Home、FiltersCompiler、Tasker、MacroDroid、Surge、
  NextDNS、Cloudflare 1.1.1.1、NetGuard、TrackerControl、PCAPdroid、Tailscale、Android Developers、Material 3、Flutter。
- 本地一手证据：本仓库 `LearningObjects/` 下 AdGuardHome-0.107.80、FlClash-0.9.3、blockads-android-7.1.1 源码（均 GPL-3.0）。
- 未能逐一核实：RethinkDNS 仓库细节、Blokada 许可证、mihomo 文档正文、Loon、Bixby 第三方 API、Google Play 具体审核口径
  —— 落地前须以各仓库 `LICENSE` 与源码复核。

## 说明

- 本规划**只新增文档，不修改任何代码**；所有功能落地须遵守 `AGENTS.md`（单文件 ≤600 行、逻辑进 Rust 单一实现、
  中文 Conventional Commits、按风险决定测试范围）。
- 外部代码引用需在 `docs/planning/research/` 记录来源（项目/版本/LICENSE/URL/改动摘要），文件头保留 SPDX 与版权声明。
