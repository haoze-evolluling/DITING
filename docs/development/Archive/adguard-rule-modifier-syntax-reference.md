# AdGuard 规则修饰符语法参考

> 基于 AdGuard 官方 Knowledge Base 整理。
> 官方文档：<https://adguard.com/kb/general/ad-filtering/create-own-filters/>
>
> 本文梳理 **Basic filtering rules（基础网络过滤规则）** 的 `$modifier` 修饰符语法，涵盖匹配控制、内容类型、网络层拦截、请求响应修改及例外控制等核心规范。

---

## 谛听 (DITING) 规则引擎适配现状

谛听在 Android 客户端（Kotlin 规则管理层 + Go 用户态隧道数据面）中对相关规则进行了针对性适配：

- **DNS 核心规则与修饰符**：
  - **基础黑白名单**：支持 `||domain.com^`、`@@||domain.com^`、通配符 `*.example.com` 以及 hosts 格式。
  - **高优先级规则**：`$important` 具备最高优先级，可有效覆盖普通例外放行规则。
  - **应用级隔离**：`$app=` 与 `$~app=`，支持按 Android 应用包名精确限制规则生效范围或排除特定应用。
  - **排除域名例外**：`$denyallow=` 与 `$~denyallow=`，支持阻断某域名的同时排除其子域名或关联域名。
  - **DNS 查询类型**：`$dnstype=` 与 `$~dnstype=`，结合查询 QType 精确判定（如 `$dnstype=AAAA`）。
  - **重写与应答覆写**：`$dnsrewrite=`，支持重定向至指定 IPv4、IPv6、CNAME 或直接阻断。
  - **对账剔除**：`$badfilter`，在流式订阅导入时预扫描并剔除失效或误报规则。
  - **正则表达式**：`/pattern/`，完整解析并支持正则语法匹配域名。
- **元素隐藏规则**：支持 `##`、`#@#`、`#?#`、`#$#` 等 Cosmetic 规则解析与管理。
- **浏览器专用修饰符**：对于纯网页资源修饰符（如 `$script`、`$image` 等），在 DNS 过滤层会进行安全忽略，防止将单类网页资源过滤错误放大为整域阻断。

---

## 1. 基础语法与核心符号

### 语法结构

```text
RULE$MODIFIER1,MODIFIER2,...
@@RULE$MODIFIER1,...
```

- **普通规则**：以匹配模式开头，`$` 后跟随一个或多个以逗号分隔的修饰符。
- **例外规则**：以 `@@` 开头，用于放行匹配的请求或禁用特定过滤行为。
- **否定逻辑**：在支持否定的修饰符或参数前加 `~` 表示排除（如 `$~third-party`、`$app=~com.example.app`）。

### 关键符号速查

| 符号 | 作用 | 示例 | 说明 |
|---|---|---|---|
| `@@` | 例外放行 | `@@||example.com^` | 允许匹配的目标通过 |
| `$` | 修饰符前缀 | `||ads.com^$script` | 引导修饰符列表 |
| `,` | 修饰符分隔符 | `$script,third-party` | 同时满足多个修饰符条件 |
| `=` | 参数赋值 | `$domain=a.com` | 为修饰符传递具体参数 |
| `\|` | 多值“或”分隔 | `$domain=a.com\|b.com` | 匹配列表中任意一个值 |
| `~` | 否定/排除 | `$~image`、`$app=~pkg` | 排除指定类型或参数值 |
| `^` | 分隔/边界符 | `||example.com^` | 匹配分隔符（如 `/`、`:`、`?` 或 URL 结尾） |
| `*` | 通配符 | `*example*` | 匹配任意字符序列 |
| `/.../` | 正则表达式 | `/[a-z]+-ads\./` | 高级正则匹配 |
| `!` | 注释行 | `! 这是一条注释` | 规则文件中的说明文本 |

---

## 2. 常用匹配与控制修饰符

| 修饰符 | 说明 | 语法与示例 |
|---|---|---|
| `$domain=` | 限定发起请求的来源/页面域名 | `\|\|ads.com^$domain=example.com\|example.org`<br>支持 `~` 排除：`$domain=example.com\|~sub.example.com` |
| `$to=` | 限定请求的目标域名（与 `$domain` 方向相反） | `*$document$to=target.example`<br>支持 `~` 排除：`$to=~trusted.com` |
| `$denyallow=` | 在宽泛规则中排除特定目标域名 | `\|\|cdn.example.com^$script,denyallow=safe.example.com`（等价于 `$to=~safe.example.com`） |
| `$app=` | 按应用包名/标识符限定（CoreLibs/Android） | `\|\|ads.com^$app=com.example.app`<br>支持多包名与排除：`$app=pkg1\|pkg2`、`$app=~pkg3` |
| `$third-party` | 仅匹配第三方请求（基于 eTLD+1 判定） | `\|\|tracker.com^$third-party` |
| `$~third-party` | 仅匹配第一方请求 | `\|\|example.com^$~third-party` |
| `$strict-third-party` | 更严格的第三方请求匹配 | `\|\|tracker.com^$strict-third-party` |
| `$strict-first-party` | 更严格的第一方请求匹配 | `\|\|cdn.example.com^$strict-first-party` |
| `$important` | 提高规则优先级，压过普通 `@@` 例外规则 | `\|\|ads.com^$important`（若例外也带 `$important` 则例外胜出） |
| `$match-case` | 对 URL 进行大小写敏感匹配 | `\|\|example.com/AdPath^$match-case` |
| `$method=` | 按 HTTP 请求方法匹配 | `\|\|example.com/api^$method=POST`<br>支持多方法与排除：`$method=GET\|POST`、`$~method=POST` |
| `$header=` | 按 HTTP Header 匹配（支持请求与响应） | `\|\|example.com^$header=set-cookie`<br>指定值或正则：`$header=set-cookie:foo`、`$header=cookie:/auth/` |
| `$badfilter` | 声明使指定规则失效（用于对账或覆盖第三方失效规则） | 原规则：`\|\|ads.com/banner.js$script`<br>覆盖：`\|\|ads.com/banner.js$script,badfilter` |

---

## 3. 内容类型修饰符

内容类型修饰符用于限制规则仅针对特定资源类型生效。

| 修饰符 | 请求类型 | 说明与示例 |
|---|---|---|
| `$document` | 页面/主文档 | 控制整个页面的访问或放行：`\|\|example.com^$document` |
| `$subdocument` | 嵌入子文档 | iframe、frame 等框架请求 |
| `$script` | JavaScript 脚本 | `\|\|example.com^$script` |
| `$stylesheet` | CSS 样式表 | 网页样式资源 |
| `$image` | 图片资源 | 包括 PNG、JPEG、WebP、SVG 等 |
| `$font` | 字体文件 | WOFF、TTF、EOT 等网络字体 |
| `$media` | 音视频媒体 | 音频与视频流媒体资源 |
| `$object` | 浏览器插件/对象 | Flash、Java Applet 等嵌入对象 |
| `$xmlhttprequest` | AJAX / Fetch | 页面异步数据请求（XHR/Fetch） |
| `$websocket` | WebSocket | WebSocket 连接请求 |
| `$ping` | Beacon / Ping | `navigator.sendBeacon` 或超链接 ping 跟踪请求 |
| `$other` | 其他未归类类型 | 无法归入上述分类的请求 |
| `$popup` | 弹窗/新标签页 | 匹配弹出窗口或新打开的页面 |
| `$all` | 所有主要类型组合 | 涵盖绝大部分资源类型及页面请求的便捷修饰符 |

> **提示**：支持多个类型组合或使用 `~` 否定排除，例如：
> - 阻断脚本和样式表：`||example.com^$script,stylesheet`
> - 阻断除图片与脚本以外的请求：`||example.com^$~image,~script`

---

## 4. 高级处理修饰符（重定向、内容修改与网络层）

此类修饰符不仅限制匹配范围，还会改变请求流程或修改响应内容。在非 MITM/代理环境下（如纯 DNS 过滤），部分修饰符会被自动忽略或需依赖相应数据面支持。

| 修饰符 | 核心功能 | 典型用法与示例 |
|---|---|---|
| `$network` | 网络层 IP 与端口过滤（匹配 IP，不接受域名） | `174.129.166.49$network`<br>`174.129.166.49:3478^$network`<br>`[2001:4860:4860::8888]:443$network` |
| `$removeparam=` | 清除 URL 中的跟踪或指定查询参数 | `\|\|example.com^$removeparam=utm_source\|utm_medium`<br>支持正则：`$removeparam=/^utm_/`、`$removeparam=fbclid` |
| `$removeheader=` | 移除指定 HTTP Header | 响应头：`$removeheader=etag`<br>请求头：`$removeheader=request:referer` |
| `$redirect=` | 重定向至本地预置桩/空资源（兼容 uBO 语法） | `\|\|example.com/ad.js$script,redirect=noopjs`<br>`\|\|example.com/ad.mp4$media,redirect=noopmp4-1s` |
| `$redirect-rule=` | 高级重定向规则模型 | `\|\|example.com^$redirect-rule=...` |
| `$replace=` | 正则替换响应正文中的文本内容 | `\|\|example.com^$replace=/advertisement/banner/` |
| `$urltransform=` | 对 URL 路径与查询部分执行转换或解码 | 正则替换：`$urltransform=/old/new/`<br>Base64/百分比解码：`$urltransform=b64\|pct` |
| `$cookie=` | 匹配、阻断或修改 Cookie | 阻断：`$cookie=session_id`<br>带属性：`$cookie=name;maxAge=3600;sameSite=lax` |
| `$csp=` | 注入或增强 Content-Security-Policy 响应头 | `\|\|example.com^$csp=script-src 'none'` |
| `$permissions=` | 修改 Permissions-Policy 响应头 | `\|\|example.com^$permissions=autoplay=()` |
| `$jsonprune=` | 对 JSON 响应数据进行结构化属性裁剪 | `\|\|example.com/api$jsonprune=ads.banner` |
| `$xmlprune=` | 对 XML 响应数据进行结构化节点裁剪 | `\|\|example.com/feed$xmlprune=//item[ad]` |
| `$referrerpolicy=` | 修改 Referrer-Policy 响应头 | `\|\|example.com^$referrerpolicy=no-referrer` |
| `$hls` | 针对 HLS 媒体流分片（m3u8/ts）的特殊过滤 | `\|\|example.com^$hls` |
| `$reason=` | 为阻断页面附加自定义解释信息（需搭配 `$document`） | `\|\|example.com^$document,reason=Custom blocked` |

---

## 5. 专用例外修饰符

配合 `@@` 使用，用于针对性关闭某类过滤机制，比整域放行（`@@||example.com^`）更加安全精细：

| 修饰符 | 短别名 | 作用说明 | 示例 |
|---|---|---|---|
| `$elemhide` | `$ehide` | 禁用该域名下的所有元素隐藏规则 | `@@\|\|example.com^$elemhide` |
| `$generichide` | `$ghide` | 禁用该域名下的通用元素隐藏规则（保留针对该域名的特定隐藏） | `@@\|\|example.com^$generichide` |
| `$specifichide` | `$shide` | 仅禁用该域名特定的元素隐藏规则 | `@@\|\|example.com^$specifichide` |
| `$genericblock` | — | 禁用通用网络阻断规则 | `@@\|\|example.com^$genericblock` |
| `$urlblock` | — | 禁用该页面发起的 URL 网络阻断 | `@@\|\|example.com^$urlblock` |
| `$content` | — | 禁用内容修改规则（`$replace`、`$jsonprune`、`$hls` 等） | `@@\|\|example.com^$content` |
| `$jsinject` | — | 阻止向页面注入自定义 JavaScript 脚本 | `@@\|\|example.com^$jsinject` |
| `$extension` | — | 控制或禁用特定/全部 Userscript 用户脚本 | `@@\|\|example.com^$extension` |

---

## 6. 规则编写与兼容性指南

### 编写最佳实践

1. **作用域最小化原则**：编写网络拦截规则时，优先结合 `$domain=`、`$to=`、`$app=` 或具体内容类型修饰符限制边界，避免宽泛的整域通配 `||example.com^` 导致误伤正常业务流量。
2. **谨慎使用 `$important`**：`$important` 会打破常规例外继承链。仅在必须强制覆盖上游通用放行规则时使用，避免滥用导致规则难以调试。
3. **分层识别多修饰符规则**：
   - 规则按 `匹配目标 -> 请求类型/方向 -> 来源/应用上下文 -> 特殊控制` 逻辑自左向右解读。
   - 示例：`||ads.com^$script,third-party,domain=site.com,~method=POST`
     - 目标匹配 `ads.com`
     - 限制为脚本请求 (`$script`) 与第三方 (`$third-party`)
     - 仅在发起方为 `site.com` 时生效 (`$domain=site.com`)
     - 排除 POST 请求 (`$~method=POST`)

### 运行环境与兼容性差异

- **网络/DNS 过滤层（谛听默认数据面）**：主要基于 DNS 报文的域名及 IP 进行判定。支持域名黑白名单、`$important`、`$app=`、`$denyallow=`、`$dnstype=`、`$dnsrewrite=`、`$badfilter` 等修饰符；对于浏览器特有的资源类型修饰符（如 `$script`、`$image` 等）会安全忽略，确保域名不被过度拦截。
- **HTTP/MITM 代理层**：具备解密或解析 HTTP 报文的能力时，方可完整生效 `$removeparam=`、`$header=`、`$replace=`、`$cookie=` 等内容级与重写修饰符。
- **官方参考文档**：
  - [AdGuard: How to create your own ad filters](https://adguard.com/kb/general/ad-filtering/create-own-filters/)
  - [AdGuard Knowledge Base (中文)](https://adguard.com/kb/zh-CN/general/ad-filtering/create-own-filters/)
