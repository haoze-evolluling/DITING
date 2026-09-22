# AdGuard 规则修饰符语法参考

> 基于 AdGuard 官方 Knowledge Base 整理。
>
> 官方文档：<https://adguard.com/kb/general/ad-filtering/create-own-filters/>
>
> 本文重点介绍 **Basic filtering rules（基础网络过滤规则）** 的 `$modifier` 语法，同时补充常用的内容类型、例外、重写/修改请求等高级修饰符。
>
> **文档整理日期：2026-09-15**

---

## 1. 最基本的语法

AdGuard 的基础规则通常采用下面的形式：

```text
RULE$MODIFIER
```

多个修饰符用逗号分隔：

```text
RULE$MODIFIER1,MODIFIER2,MODIFIER3
```

例如：

```text
||example.com^$script,third-party
```

表示：只匹配来自 `example.com` 的脚本请求，并要求该请求属于第三方请求。

### 例外规则

在规则最前面加 `@@`，表示例外/放行：

```text
@@||example.com^$document
```

通常用于取消某个阻断规则，或者禁用某类过滤行为。

### 否定修饰符

很多限定类修饰符可以使用 `~` 表示“排除”：

```text
||example.com^$~image,~script
```

含义是匹配 `example.com`，但排除图片和脚本请求。

---

## 2. 最常用的修饰符

| 修饰符 | 作用 | 示例 |
|---|---|---|
| `$domain=` | 限定发起页面/来源域名 | `||ads.com^$domain=example.com` |
| `$denyallow=` | 匹配目标时排除指定域名 | `||ads.com^$denyallow=example.com` |
| `$third-party` | 仅匹配第三方请求 | `||ads.com^$third-party` |
| `$~third-party` | 仅匹配第一方请求 | `||ads.com^$~third-party` |
| `$strict-third-party` | 更严格的第三方判断 | `||ads.com^$strict-third-party` |
| `$strict-first-party` | 更严格的第一方判断 | `||cdn.example.com^$strict-first-party` |
| `$important` | 提高规则优先级，可压过普通例外 | `||ads.com^$important` |
| `$match-case` | URL 大小写敏感匹配 | `||example.com/Ad^$match-case` |
| `$method=` | 按 HTTP 方法匹配 | `||example.com^$method=GET|POST` |
| `$to=` | 限定请求目标域名 | `*$document$to=example.com` |
| `$app=` | 按应用匹配（主要用于 CoreLibs 产品） | `||ads.com^$app=org.example.app` |
| `$header=` | 按 HTTP Header 匹配 | `||example.com^$header=set-cookie` |

---

## 3. `$domain`：按来源域名限制

### 基本语法

```text
$domain=domain1|domain2|domain3
```

示例：

```text
||ads.example^$domain=example.com|example.org
```

表示：仅当请求来源页面属于 `example.com` 或 `example.org` 时才匹配。

### 排除域名

使用 `~`：

```text
||ads.example^$domain=example.com|~sub.example.com
```

表示允许 `example.com`，但排除 `sub.example.com`。

### 通配符

可以使用 `*`：

```text
$domain=example.*
```

用于匹配以指定部分开头的域名形式。

> **注意：** `$domain` 的语义主要与“请求来源/Referrer 页面”有关。它并不等同于“目标 URL 必须属于该域名”。对于目标域名限制，应关注 `$to`。

---

## 4. `$denyallow`：允许目标域名例外

基本形式：

```text
$denyallow=domain1|domain2
```

它适合在较宽泛的匹配条件中排除特定目标域名。

例如：

```text
||cdn.example.com^$script,denyallow=trusted.example.com
```

可以理解为：匹配脚本请求，但对指定目标域名不执行这个规则。

也可以使用否定 `$to` 表达类似逻辑：

```text
$denyallow=a.com|b.com
```

在相应场景下等价于：

```text
$to=~a.com|~b.com
```

---

## 5. 内容类型修饰符

内容类型修饰符用于限制规则只作用于特定类型的请求。

### 常用类型

| 修饰符 | 请求类型 |
|---|---|
| `$document` | 页面/主文档 |
| `$subdocument` | iframe/frame 等子文档 |
| `$script` | JavaScript 等脚本 |
| `$stylesheet` | CSS 样式表 |
| `$image` | 图片 |
| `$font` | 字体 |
| `$media` | 音视频媒体 |
| `$object` | 浏览器对象/插件资源 |
| `$xmlhttprequest` | XHR/AJAX 请求 |
| `$websocket` | WebSocket |
| `$ping` | Beacon / link ping |
| `$other` | 未归类的其他请求 |
| `$all` | 所有主要请求类型的组合 |

### 示例

只阻止图片：

```text
||example.com^$image
```

只阻止脚本和 CSS：

```text
||example.com^$script,stylesheet
```

排除图片、脚本和 CSS：

```text
||example.com^$~image,~script,~stylesheet
```

### `$popup`

用于匹配弹窗/新页面类请求：

```text
||example.com^$popup
```

在当前 AdGuard 规则模型中，`$popup` 与文档级请求密切相关。

---

## 6. `$third-party` 与第一方请求

### `$third-party`

只匹配第三方请求：

```text
||tracker.example^$third-party
```

### `$~third-party`

表示排除第三方，即只匹配第一方范围：

```text
||example.com^$~third-party
```

### `$strict-third-party`

提供更严格的第三方判断：

```text
||tracker.example^$strict-third-party
```

### `$strict-first-party`

提供更严格的第一方判断：

```text
||example.com^$strict-first-party
```

> 实际使用时，第一方/第三方判断涉及 eTLD+1、来源站点以及请求目标，不能简单理解成“两个域名字符串是否相同”。

---

## 7. `$method`：按 HTTP 方法匹配

语法：

```text
$method=GET|POST|PUT
```

示例：

```text
||example.com/api^$method=POST
```

只匹配 POST 请求。

多个方法：

```text
||example.com/api^$method=GET|POST|PUT
```

排除某个方法：

```text
||example.com/api^$~method=POST
```

> 具体支持的方法以及产品兼容性应以当前使用的 AdGuard 产品为准。

---

## 8. `$match-case`：大小写敏感

默认 URL 匹配通常不区分大小写。

加上：

```text
$match-case
```

后进行大小写敏感匹配。

示例：

```text
||example.com/Ads^$match-case
```

此时 `Ads` 与 `ads` 不再视为相同文本。

---

## 9. `$important`：提高规则优先级

这是一个非常重要的高级修饰符：

```text
||example.com^$important
```

普通阻断规则可能被普通 `@@` 例外规则覆盖，而 `$important` 可以让阻断规则拥有更高优先级。

例如：

```text
||example.org^$important
@@||example.org^
```

第一条 `$important` 阻断规则可以压过普通例外规则。

若例外本身也带 `$important`：

```text
||example.org^$important
@@||example.org^$important
```

则例外规则可以再次取得更高优先级。

> 因此 `$important` 应谨慎使用，否则容易让后续维护和排查规则冲突变得困难。

---

## 10. `$header`：按 HTTP Header 匹配

语法：

```text
$header=HEADER-NAME
```

或者：

```text
$header=HEADER-NAME:VALUE
```

示例：

```text
||example.com^$header=set-cookie
```

匹配存在 `Set-Cookie` Header 的响应。

指定值：

```text
||example.com^$header=set-cookie:foo
```

也支持正则值，例如：

```text
@@||example.com^$header=set-cookie:/foo\, bar\$/
```

> `$header` 属于较高级的规则。它依赖 Header 已经被接收，在请求更早阶段已经被阻断或重定向时可能无法应用。

---

## 11. `$to`：按请求目标限制

`$to` 与 `$domain` 的方向不同：

- `$domain`：主要限制请求的**来源/发起页面**。
- `$to`：限制请求的**目标域名**。

例如：

```text
*$document,domain=example.com,to=target.example
```

表示只处理来自 `example.com`，并且目标为 `target.example` 的文档请求。

也可以否定：

```text
$to=~trusted.example.com
```

表示排除目标为 `trusted.example.com` 的请求。

---

## 12. `$app`：按应用限定

主要用于支持 CoreLibs 的 AdGuard 产品，例如 AdGuard for Android、Windows、Mac、Linux 等。

Android 示例：

```text
||example.com^$app=org.example.app
```

也可以指定多个应用：

```text
||example.com^$app=org.example.app1|org.example.app2
```

排除应用：

```text
||example.com^$app=~org.example.app1
```

Android 中这里通常使用应用包名，例如：

```text
$app=org.mozilla.firefox
```

---

## 13. `$document`：页面级规则

最常见的用途是控制整个网站：

```text
||example.com^$document
```

如果配合 `@@`：

```text
@@||example.com^$document
```

可以对该网站及其子域执行页面级的过滤例外。

这是一个非常强的规则类型，使用时要特别注意作用范围。

---

## 14. 常见高级修饰符

这些修饰符已经不只是“缩小匹配范围”，而是在改变请求处理方式。

| 修饰符 | 主要用途 | 示例 |
|---|---|---|
| `$redirect=` | 将请求重定向到 AdGuard 本地资源 | `||example.com/script.js$script,redirect=noopjs` |
| `$redirect-rule=` | 重定向规则的另一种高级形式 | `||example.com^$redirect-rule=...` |
| `$removeparam=` | 从 URL 查询参数中移除参数 | `||example.com^$removeparam=utm_source` |
| `$removeheader=` | 删除指定 HTTP Header | `||example.com^$removeheader=etag` |
| `$replace=` | 修改响应内容中的文本 | `||example.com^$replace=/foo/bar/` |
| `$urltransform=` | 对请求 URL 执行转换 | `$urltransform=/old/new/` |
| `$cookie=` | 修改/删除匹配的 Cookie | `$cookie=__utm[a-z]` |
| `$csp=` | 增强响应的 Content-Security-Policy | `$csp=script-src 'none'` |
| `$permissions=` | 修改 Permissions Policy | `$permissions=autoplay=()` |
| `$jsonprune=` | 对 JSON 内容做结构化删除 | `$jsonprune=...` |
| `$xmlprune=` | 对 XML 内容做结构化删除 | `$xmlprune=...` |
| `$referrerpolicy=` | 修改 Referrer Policy | `$referrerpolicy=no-referrer` |
| `$hls` | 处理 HLS 媒体流相关内容 | `||example.com^$hls` |
| `$inline-script` | 匹配/处理内联脚本相关内容 | `$inline-script` |
| `$inline-font` | 匹配/处理内联字体相关内容 | `$inline-font` |
| `$network` | 按 IP/端口进行网络级阻断/放行 | `174.129.166.49$network` |
| `$reason=` | 为阻断页面添加自定义原因 | `||example.com^$document,reason=Blocked` |

> 高级修饰符的兼容性差异明显。特别是 `$replace`、`$network`、`$jsonprune`、`$xmlprune`、`$urltransform` 等，应查看当前产品的兼容性说明。

---

## 15. `$removeparam`：去除 URL 参数

这是实际编写规则时非常常用的修饰符。

例如删除 Google Analytics 的参数：

```text
||example.com^$removeparam=utm_source
```

可以指定多个参数：

```text
||example.com^$removeparam=utm_source|utm_medium|utm_campaign
```

也可以使用正则表达式：

```text
||example.com^$removeparam=/^utm_/ 
```

更常见的写法是：

```text
||example.com^$removeparam=/^utm_/ 
```

表示匹配以 `utm_` 开头的查询参数名称。

### 典型用途

```text
$removeparam=utm_source
```

```text
$removeparam=fbclid
```

```text
$removeparam=gclid
```

这些规则并不是“阻止请求”，而是修改请求 URL。

---

## 16. `$redirect`：将请求重定向到本地资源

示例：

```text
||example.org/script.js$script,redirect=noopjs
```

含义是：匹配脚本请求，并将其重定向到名为 `noopjs` 的本地资源。

另一个例子：

```text
||example.org/test.mp4$media,redirect=noopmp4-1s
```

关闭某类重定向规则，可以使用例外：

```text
@@||example.org^$redirect
```

> `$redirect` 使用的是 AdGuard 本地资源体系，并且与 uBlock Origin 的资源重定向语法存在兼容关系。

---

## 17. `$redirect-rule`

它同样用于请求重定向，但行为和 `$redirect` 的规则匹配模型不同。

对于普通使用者，除非你正在维护高级过滤器或需要兼容现成规则集，否则优先理解 `$redirect` 即可。

---

## 18. `$cookie`

示例：

```text
||example.org^$cookie=NAME
```

匹配名为 `NAME` 的 Cookie。

删除/阻止所有来自某域的 Cookie：

```text
||example.org^$cookie
```

使用正则匹配 Cookie 名称：

```text
$cookie=/__utm[a-z]/
```

还可以指定过期时间和 SameSite：

```text
||example.org^$cookie=NAME;maxAge=3600;sameSite=lax
```

---

## 19. `$csp`

`$csp` 不会直接阻止匹配的请求，而是修改页面响应中的 Content Security Policy。

例如：

```text
||example.org^$csp=script-src 'none'
```

它属于安全策略层面的高级规则。

通常需要理解 CSP 后再使用。

---

## 20. `$removeheader`

删除 HTTP Header。

响应 Header：

```text
||example.org^$removeheader=etag
```

请求 Header：

```text
||example.org^$removeheader=request:referer
```

其中 `request:` 明确表示处理请求 Header；默认情况下主要针对响应 Header。

例外：

```text
@@||example.org^$removeheader
```

可以取消该 URL 范围内的 `$removeheader` 规则。

---

## 21. `$urltransform`

用于对请求 URL 的路径/查询部分进行转换。

基础替换结构：

```text
$urltransform=/正则表达式/替换内容/修饰符
```

还支持 URL 解码阶段，例如：

```text
$urltransform=pct
```

以及 Base64 解码：

```text
$urltransform=b64
```

多个转换可以使用 `|` 串起来：

```text
$urltransform=/old/new/|pct
```

> `$urltransform` 通常在 `$removeparam` 之前执行，因此涉及多个 URL 修改规则时要注意处理顺序。

---

## 22. `$network`：网络层 IP 规则

`$network` 与普通 URL 过滤不同，它匹配的是 **IP 地址**，而不是域名。

例如：

```text
174.129.166.49$network
```

阻止该 IP。

指定端口：

```text
174.129.166.49:3478^$network
```

IPv6：

```text
[2001:4860:4860::8888]:443$network
```

正则：

```text
/.+:3[0-9]{4}/$network
```

> 官方明确指出 `$network` 是网络/IP 层规则，只能使用 IP，不能直接用域名作为匹配目标。

---

## 23. `$permissions`

用于修改响应中的 Permissions Policy。

例如禁止自动播放：

```text
||example.org^$permissions=autoplay=()
```

多个 feature：

```text
||example.org^$permissions=storage-access=()\,camera=()
```

或者在支持的版本中使用 `|` 分隔：

```text
||example.org^$permissions=storage-access=()|camera=()
```

---

## 24. `$reason`

给阻断页面增加自定义解释信息。

示例：

```text
||example.org^$document,reason=Blocked by custom rule
```

它主要用于规则调试、用户提示和规则管理场景，并且要求与 `$document` 内容类型结合使用。

---

## 25. 例外修饰符

除了 `@@`，AdGuard 还提供一批“关闭某类过滤”的专用例外修饰符。

### `$elemhide`

禁用元素隐藏规则：

```text
@@||example.com^$elemhide
```

短别名：

```text
@@||example.com^$ehide
```

### `$generichide`

禁用通用元素隐藏：

```text
@@||example.com^$generichide
```

短别名：

```text
@@||example.com^$ghide
```

### `$specifichide`

禁用指定域名下的特定元素隐藏/CSS 规则：

```text
@@||example.com^$specifichide
```

短别名：

```text
@@||example.com^$shide
```

### `$genericblock`

禁用通用网络阻断规则：

```text
@@||example.com^$genericblock
```

### `$urlblock`

禁用页面发起的 URL 阻断等行为：

```text
@@||example.com^$urlblock
```

### `$content`

禁用 HTML filtering、`$hls`、`$replace`、`$jsonprune` 等内容修改规则：

```text
@@||example.com^$content
```

### `$jsinject`

阻止 JavaScript 注入类规则：

```text
@@||example.com^$jsinject
```

### `$extension`

控制特定 userscript 或全部 userscript：

```text
@@||example.com^$extension
```

---

## 26. `$badfilter`：禁用已有规则

`$badfilter` 可以让一条规则失效。

例如原规则：

```text
||example.com/ads.js$script
```

可以通过：

```text
||example.com/ads.js$script,badfilter
```

使对应规则失效。

这在维护第三方过滤器、无法直接修改原规则时特别有用。

---

## 27. `$all`

`$all` 是一种方便的组合形式，用于覆盖主要请求类型：

```text
||example.com^$all
```

它可以理解为一个组合性的“所有主要内容类型 + 页面/弹窗范围”规则，而不是一个普通单一 MIME 类型。

---

## 28. 修饰符组合

多个修饰符可以组合使用：

```text
||ads.example^$script,third-party,domain=example.com
```

逻辑可以拆成：

1. 目标匹配 `ads.example`
2. 请求必须是脚本
3. 必须是第三方请求
4. 来源页面必须属于 `example.com`

再例如：

```text
||example.com/track^$xmlhttprequest,domain=example.org|example.net,important
```

表示：

- 只匹配 XHR/AJAX；
- 来源为 `example.org` 或 `example.net`；
- 规则具有较高优先级。

---

## 29. 复杂规则如何阅读

看到：

```text
||ads.example.com^$script,third-party,domain=example.com|example.org,~method=POST
```

可以按下面顺序理解：

```text
||ads.example.com^
```

匹配目标 URL。

```text
$script
```

只匹配脚本。

```text
,third-party
```

只匹配第三方请求。

```text
,domain=example.com|example.org
```

来源页面必须属于指定域名。

```text
,~method=POST
```

排除 POST 请求。

因此，这是一条“针对指定来源站点的第三方脚本请求进行阻断，但不处理 POST”的规则。

---

## 30. 规则语法中的几个关键符号

| 符号 | 含义 |
|---|---|
| `@@` | 例外/放行规则 |
| `$` | 修饰符起始位置 |
| `,` | 多个修饰符之间的分隔符 |
| `=` | 给修饰符传递参数 |
| `|` | 多个修饰符值之间的分隔符，具体语义取决于修饰符 |
| `~` | 否定/排除 |
| `^` | AdGuard URL 分隔符/边界匹配符 |
| `*` | 通配符 |
| `/.../` | 正则表达式形式（适用于支持正则的修饰符/规则） |
| `!` | 注释行开头 |

---

## 31. 常用实战模板

### 仅阻止第三方脚本

```text
||tracker.example^$script,third-party
```

### 只在某个网站上生效

```text
||tracker.example^$domain=example.com
```

### 某网站下只阻止图片

```text
||ads.example^$image,domain=example.com
```

### 阻止指定网站的所有页面访问

```text
||example.com^$document
```

### 放行整个网站

```text
@@||example.com^$document
```

### 删除跟踪参数

```text
||example.com^$removeparam=utm_source|utm_medium|utm_campaign
```

### 删除所有 `utm_` 参数

```text
||example.com^$removeparam=/^utm_/
```

### 禁止某站点元素隐藏

```text
@@||example.com^$elemhide
```

### 禁止通用广告规则

```text
@@||example.com^$genericblock
```

### 禁止通用元素隐藏

```text
@@||example.com^$generichide
```

### 让规则拥有高优先级

```text
||example.com^$important
```

### 禁用某条过滤器规则

```text
||example.com/banner.js$script,badfilter
```

---

## 32. 修饰符选择思路

遇到一条需求时，可以优先按以下思路判断：

```text
需要阻止/放行什么？
        │
        ├─ URL 请求本身
        │      └─ 基础规则 + 内容类型修饰符
        │
        ├─ 限定来源网站
        │      └─ $domain=
        │
        ├─ 限定目标网站
        │      └─ $to=
        │
        ├─ 只处理第三方
        │      └─ $third-party
        │
        ├─ 按 HTTP 方法区分
        │      └─ $method=
        │
        ├─ 修改 URL 参数
        │      └─ $removeparam=
        │
        ├─ 修改 Header
        │      └─ $removeheader= / $header=
        │
        ├─ 修改响应内容
        │      └─ $replace / $jsonprune / $xmlprune
        │
        ├─ 修改安全策略
        │      └─ $csp / $permissions / $referrerpolicy
        │
        └─ 调整规则优先级
               └─ $important / @@ / $badfilter
```

---

## 33. 兼容性非常重要

同一个修饰符不一定在所有 AdGuard 产品中都可用。

当前官方文档明确区分了：

- AdGuard for Windows
- AdGuard for macOS
- AdGuard for Android
- AdGuard for Linux
- AdGuard Browser Extension
- AdGuard Chrome MV3
- AdGuard for iOS
- AdGuard for Safari
- AdGuard Content Blocker

例如 `$network` 主要适用于 Windows、Mac、Android 等具备网络层能力的产品；`$replace`、`$jsonprune`、`$xmlprune` 等高级规则也存在明显的平台限制。

因此不要只看到“AdGuard 支持这个修饰符”，就默认它在所有客户端都支持。

---

## 34. 与 Adblock Plus / uBlock Origin 的关系

AdGuard 的基础过滤语法历史上基于 Adblock Plus（ABP）语法，之后扩展了许多自己的规则类型和高级修饰符。

AdGuard 还兼容部分 uBlock Origin / ABP 生态中的语法，例如 `$redirect` 相关资源重定向机制。

因此：

```text
AdGuard 规则
≈ ABP 基础语法
+ AdGuard 扩展
+ 部分 uBlock Origin 兼容语法
```

但三者并不是完全等价的语法集合，尤其是高级规则和脚本/脚本小程序部分，不能简单认为“uBlock 能跑，AdGuard 就一定完全一样”。

---

## 35. 编写规则时的建议

### 先缩小作用范围

优先使用：

```text
$domain=
$to=
$script
$image
$xmlhttprequest
$third-party
```

而不是直接：

```text
||example.com^
```

否则规则可能误伤正常请求。

### `$important` 不要滥用

它会改变规则优先级，适合处理明确的规则冲突，而不是作为普通“保险开关”。

### 高级修改规则要先确认平台

尤其是：

```text
$replace
$redirect
$network
$removeheader
$removeparam
$urltransform
$jsonprune
$xmlprune
$csp
$permissions
```

使用之前应先确认实际客户端和版本支持情况。

### 规则出现问题时检查请求上下文

重点检查：

- 请求 URL
- 来源页面 URL
- 第三方/第一方状态
- Content-Type / 请求类型
- HTTP 方法
- Request / Response Header
- 是否存在更高优先级规则
- 当前产品是否支持该 modifier

---

## 36. 官方参考

AdGuard 官方文档：

- [How to create your own ad filters](https://adguard.com/kb/general/ad-filtering/create-own-filters/)
- [AdGuard Knowledge Base（中文）](https://adguard.com/kb/zh-CN/general/ad-filtering/create-own-filters/)

官方文档是不断更新的。由于修饰符的数量、兼容性和实现细节可能变化，实际写过滤器时应以当前官方文档及当前客户端版本为准。

