# 多语言（国际化）工作流

本项目使用 Flutter 官方 `gen-l10n` + ARB 资源实现中文 / 英文切换，架构可扩展到更多语言：
新增语言只需在 `lib/l10n/` 增加 `app_<locale>.arb`，`AppL10n.supportedLocales` 会自动包含它，
`lib/state/settings_providers.dart` 的 `AppLanguageMode` 增加一个枚举项即可出现在设置页。

## 结构

- `l10n.yaml`：`arb-dir: lib/l10n`，模板文件 `app_zh.arb`，输出类 `AppL10n`。
- `lib/l10n/app_zh.arb` / `app_en.arb`：全部文案，中文为模板（键的占位符定义在 zh）。
- `lib/app/l10n/l10n.dart`：
  - `context.l10n`：Widget 内取文案。
  - `currentL10n` / `setCurrentL10n()`：没有 `BuildContext` 的 state / data / service 层使用，
    由 `DitingApp.builder` 在语言变化时刷新。
- `lib/app/l10n/ui_strings.dart`：`AppUiLocalizations` 兼容层，全部委托给 ARB。
- 设置入口：`lib/state/settings_providers.dart`（`AppLanguageMode.system/chinese/english`、
  `appLocaleProvider`），页面 `SettingsLanguagePage`。

## 约定

1. 枚举的展示字段改成方法：`String label(AppL10n l10n) => switch (this) {...}`，
   枚举本身保持 `const`。
2. `const` 的本地化列表改成函数：`List<X> items(AppL10n l10n)`。
3. `part of` 文件不能写 import，import 放在父库文件上。
4. 没有 `BuildContext` 的纯函数追加一个 `AppL10n l10n` 位置参数（或使用 `currentL10n`）。
5. 会缓存结果的 `Provider` 不要读 `currentL10n`：它只在依赖变化时重算，切换语言不会触发，
   会把上一个语言的文案一直留着。把 `AppL10n` 当 `Provider.family` 的参数传进去
   （见 `visibleFeatureCategoriesProvider`），由页面传 `context.l10n`。
6. 引擎 / 数据层的协议字符串（如 IP 质量的 `'住宅'`、`'命中'` 解析映射）保持中文，
   只转换展示文案；`lib/data/agent` 的 AI 提示词模板按设计保留中文。

## 工具（`tool/i18n/`）

| 脚本 | 作用 |
| --- | --- |
| `merge_arb.py <batch.json>` | 把 `{key: [zh, en]}`（可带 `placeholders`）合并进两个 ARB；同文案不同键会报错 |
| `apply.py <batch.json> <files...>` | 把批次的**精确中文原文**替换为 `context.l10n.key`（`--l10n=current` 用 `currentL10n`），并补 import |
| `fix_const.py` | 按 analyzer 的 `invalid_constant` 等报错去掉多余 `const` |
| `fix_labels.py` | 给报错的 `.label/.title/...` 访问补上 `(context.l10n)` |
| `fix_parts.py` | 修正 `part of` 文件的 import（保留在父库上） |
| `add_imports.py` / `drop_unused.py` | 补 / 删 l10n import |
| `find_key.py <文案>` | 查某个中文（或 `--en` 英文）文案已有哪些 key，避免重复建键 |

标准流程：

```bash
# 1. 写批次 JSON（tool/i18n/batches/*.json）
python tool/i18n/merge_arb.py tool/i18n/batches/xxx.json
flutter gen-l10n
python tool/i18n/apply.py tool/i18n/batches/xxx.json lib/pages/xxx/*.dart
# 2. 修编译错误
for i in 1 2 3; do python tool/i18n/fix_const.py < <(flutter analyze lib 2>&1); done
python tool/i18n/fix_parts.py
# 3. 找出漏掉的多行 / 插值字符串
rg -n "[\p{Han}]" --glob "*.dart" lib/<dir> | rg -v "^\S+:[0-9]+: *//"
# 4. 验证
flutter analyze lib && flutter test
```

多行字符串与插值需要手工替换（`apply.py` 只处理单行精确匹配）；
用 `write` 工具写一次性 patch 脚本比 shell heredoc 更可靠（Windows 下 heredoc 会截断长内容）。

## 已完成范围

基础设施、共享组件、应用外壳、首页与仪表盘、状态层枚举与提示、数据层枚举与预设、
外观 / 设置 / 规则 / 订阅 / 流量 / 请求观测 / 日志 / 关于 / 开发者选项 / IP 质量 /
工作模式 / 网络诊断工具 / 自定义资源 / 按需连接 / 服务器模式 / 故障排查，以及功能中心的
镜像、隐藏功能、缓存、服务显示、应用规则、应用选择、日志模式、引导解析等页面。

功能中心其余页面：CA 证书、订阅工具（自动更新与镜像模板）、规则控制与拦截响应、
HTTPS 流量检查、数据清理、备份与迁移、WebDAV 云同步、出站代理、解析模式、
服务商管理、应用独立规则（含详情面板）、AI 分析 / 厂商管理 / 厂商编辑 / 参数与提示词 /
分析结果面板，以及「其他设置」页。

数据层：`dashboard_models`（状态与卡片枚举）、`notification_status_text`、
`backup_models` / `backup_importer` / `backup_exporter` / `backup_import_*`、
`dav_client`、`agent_api_client`、`agent_api_text_parser`、`app_update_checker`、
`platform_bridge`、`ca_bridge`、`outbound_proxy_bridge`、`update_bridge`、
`dns_latency_bridge`、`permissions_bridge`、`font_repository`、`data_cleanup_service`、
`subscription_fetcher` / `subscription_url`、`mock_system`（免责声明全文）、
`site_latency_categories`、`log_dashboard_rows` / `log_dashboard_models`、
`mock_content` 的运行时长与 `legacy_settings` 的默认标语。

## 按设计保留中文的部分

- `lib/data/agent/`：AI 提示词模板（`agent_prompts.dart`、`agent_settings_pages.dart`
  里的预设提示词正文）、流量统计摘要（`agent_traffic_summary.dart`）与 Markdown 判读关键词
  （`markdown_inline.dart`）。提示词与模型输出保持同一种语言，报告才不会中英混排。
- 协议 / 解析映射：IP 质量的 `'住宅' / '命中' / '限流'` 等状态与类型、`'机房' / '移动'`
  分类关键字，`dns_query_repository` / `http_request_repository` 的 SQL 与状态码，
  `site_latency_targets` 的站点名（品牌名），`mock_providers` 的演示数据，
  `config_resource_store` 与 `recognition_members` 的配置校验（仅 debug / 开发可见）。
- 代码注释与文档保持中文。

## 测试注意事项

- `test/support/app_host.dart` 与 `test/support/test_hooks.dart` 固定为中文环境，
  断言中文文案的用例不需要改动。
- 枚举字段变成方法后，测试里的 `kind.title` 要改成 `kind.title(l10n)`；
  `l10n` 可用 `lookupAppL10n(const Locale('zh'))`（需 `import 'package:flutter/widgets.dart'
  show Locale;`）或测试宿主里的实例。
- 数据层现在用 `currentL10n`：断言错误文案的用例依赖测试宿主先设定中文环境；
  常量构造（如 `FontPickResult.unavailable()`）因此不再是 `const`。
- `test/app_layer_test.dart` 的枚举文案守卫会遍历 `AppL10n.supportedLocales`。
## 测试注意事项

- `test/support/app_host.dart` 与 `test/support/test_hooks.dart` 固定为中文环境，
  断言中文文案的用例不需要改动。
- 枚举字段变成方法后，测试里的 `kind.title` 要改成 `kind.title(l10n)`；
  `l10n` 可用 `lookupAppL10n(const Locale('zh'))` 或测试宿主里的实例。
- `test/app_layer_test.dart` 的枚举文案守卫会遍历 `AppL10n.supportedLocales`。
