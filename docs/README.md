# 项目文档库

本目录收录 DITING 项目的全部文档,按文档类型与用途分类存放。新增文档时请归档到对应分类目录,并同步更新本索引。

## 目录结构

| 目录 | 用途 | 收录范围 |
|------|------|----------|
| `development/` | 开发与构建 | 构建环境、编译流程、构建问题排查等面向开发者的文档 |
| `features/` | 功能与运营 | 功能机制说明、云端配置维护流程等运营类文档 |
| `refactor/` | 重构规划 | 架构调整与重构方案的设计、评审与实施记录 |
| `assets/` | 图片与静态资源 | 文档引用或项目维护所需的图片等静态资源 |

## 文档索引

### development/

- [Go AAR 构建记录](development/aar-build-notes.md) — Go 隧道 AAR 的编译过程、构建参数、遇到的问题与解决办法
- [AdGuard 规则修饰符语法参考](development/adguard-rule-modifier-syntax-reference.md) — 基于 AdGuard 官方文档整理的基础过滤规则 `$modifier` 语法参考
- [DNS 过滤效果差距排查报告](development/dns-filtering-gap-analysis.md) — 谛听与 AdGuard 过滤效果差距的排查过程、根因分析与优化路线图
- [Android 签名证书管理与发布签名规范](development/android-signing-certificate-management.md) — 全新 4096 位 Android 签名证书规格、指纹、Google Drive 私有保管与构建配置指引

### features/

- [云控贡献者名单说明](features/recognition-members.md) — 赞助者与共建者名单的云控机制、配置格式与维护流程

### refactor/

- [规则订阅按类型拆分重构规划](refactor/subscription-type-split.md) — 将混合订阅模型拆分为黑白名单与 hosts 两条独立链路的重构方案

### assets/

- `alipay_code.png` — 支付宝付款码图片(README 赞助章节引用)
- `wechatpay_code.png` — 微信付款码图片(README 赞助章节引用)

## 新增文档规范

1. **按用途选择目录**:开发与构建相关放 `development/`;功能机制与运营配置放 `features/`;图片等静态资源放 `assets/`。
2. **文件命名**:使用小写英文单词与连字符,如 `new-feature-notes.md`;配图资源按内容命名。
3. **相互引用**:文档之间的链接一律使用相对路径。
4. **分类扩展**:若现有分类均不适合,可新建分类目录,并在本索引中补充目录说明与文档条目。
5. **更新索引**:每次新增或移动文档后,同步更新上方的目录结构与文档索引,保持索引与实际文件一致。
