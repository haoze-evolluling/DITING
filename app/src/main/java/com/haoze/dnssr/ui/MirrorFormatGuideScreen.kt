package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.dnssr.ui.components.SettingsScaffold

private val mirrorFormatMarkdown = """
镜像站模板会把原始订阅地址嵌入镜像服务地址。添加模板时，请先确认镜像服务要求的写法，再选择合适的占位符。

## 一、先看一个完整例子

假设原始订阅地址是 `https://github.com/example/dnssr/releases/latest/download/rules.txt`。

模板 `https://ghproxy.example.com/{url}` 会生成：

`https://ghproxy.example.com/https://github.com/example/dnssr/releases/latest/download/rules.txt`

这里的 `{url}` 会被完整的原始地址替换。大多数“在路径后面直接拼接原地址”的镜像服务，都使用这种写法。

## 二、六个占位符分别是什么

### `{url}`：完整原始地址

保留原始地址的协议、主机、路径和查询参数。例如 `https://mirror.example.com/{url}`。

适合：镜像服务要求把原始 URL 直接放到路径中的情况。

### `{urlEncoded}`：编码后的完整地址

会把原始地址编码后再放入模板。例如 `https://mirror.example.com/?url={urlEncoded}`。

适合：镜像服务通过 `url` 查询参数接收地址的情况。查询参数通常应优先使用这个占位符。

### `{scheme}`：原地址协议

例如原地址是 `https://github.com/a/b`，那么 `{scheme}` 就是 `https`。

### `{host}`：原地址主机

例如原地址是 `https://github.com/a/b`，那么 `{host}` 就是 `github.com`。

### `{path}`：原地址路径

例如原地址是 `https://github.com/a/b`，那么 `{path}` 就是 `/a/b`，不包含查询参数。

### `{pathAndQuery}`：路径和查询参数

例如原地址是 `https://github.com/a/b?download=1`，那么 `{pathAndQuery}` 就是 `/a/b?download=1`。

## 三、常见写法举例

1. 路径替换型：`https://ghproxy.example.com/{url}`。原地址会整体拼接到镜像域名后。
2. 查询参数型：`https://mirror.example.com/?url={urlEncoded}`。原地址会作为 `url` 参数传给镜像服务。
3. 主机转发型：`https://mirror.example.com/{scheme}/{host}{pathAndQuery}`。镜像服务可以根据原协议、主机和路径转发请求。

如果镜像服务的文档没有特别说明，建议先尝试第一种 `{url}` 写法；如果文档明确要求 `?url=` 参数，则使用 `{urlEncoded}`。

## 四、添加前检查

* 模板必须以 `http://` 或 `https://` 开头。
* 模板至少包含一个占位符，否则镜像地址不会包含原始订阅地址。
* 查询参数中的原始 URL 通常要使用 `{urlEncoded}`，不要直接替换成 `{url}`。
* 不要把固定的路径和 `{path}`、`{pathAndQuery}` 重复拼接，避免生成错误地址。
* 只添加你信任的镜像服务。订阅地址会被发送给镜像站处理。
""".trimIndent()

private val mirrorFormatMarkdownEnglish = """
A mirror template embeds the original subscription URL into a mirror service URL. Before adding one, confirm the format required by the mirror service and choose the appropriate placeholder.

## I. A complete example

Suppose the original subscription URL is `https://github.com/example/dnssr/releases/latest/download/rules.txt`.

The template `https://ghproxy.example.com/{url}` produces:

`https://ghproxy.example.com/https://github.com/example/dnssr/releases/latest/download/rules.txt`

`{url}` is replaced with the complete original URL. Most mirror services that append the original URL directly to a path use this form.

## II. The six placeholders

### `{url}`: complete original URL

Keeps the original scheme, host, path, and query parameters. For example: `https://mirror.example.com/{url}`.

Use it when the mirror service expects the original URL directly in the path.

### `{urlEncoded}`: encoded complete URL

Encodes the original URL before inserting it, for example `https://mirror.example.com/?url={urlEncoded}`.

Use it when the mirror service receives the URL as a query parameter. Query parameters normally require this placeholder.

### `{scheme}`: original scheme

For `https://github.com/a/b`, `{scheme}` is `https`.

### `{host}`: original host

For `https://github.com/a/b`, `{host}` is `github.com`.

### `{path}`: original path

For `https://github.com/a/b`, `{path}` is `/a/b`, without query parameters.

### `{pathAndQuery}`: path and query

For `https://github.com/a/b?download=1`, `{pathAndQuery}` is `/a/b?download=1`.

## III. Common forms

1. Path replacement: `https://ghproxy.example.com/{url}` appends the complete URL after the mirror host.
2. Query parameter: `https://mirror.example.com/?url={urlEncoded}` passes the original URL as the `url` parameter.
3. Host forwarding: `https://mirror.example.com/{scheme}/{host}{pathAndQuery}` forwards the original scheme, host, and path.

Unless the mirror documentation says otherwise, try `{url}` first. If the documentation requires `?url=`, use `{urlEncoded}`.

## IV. Check before adding

* The template must start with `http://` or `https://`.
* It must contain at least one placeholder, otherwise the mirror URL will not include the original subscription URL.
* Use `{urlEncoded}` for original URLs in query parameters; do not replace it with `{url}`.
* Do not duplicate fixed paths with `{path}` or `{pathAndQuery}`.
* Add only mirror services you trust. The subscription URL is sent to the mirror service.
""".trimIndent()

private val mirrorCodeToken = Regex("""(https?://[^\s{}]+|[{][A-Za-z]+[}])""")

@Composable
fun MirrorFormatGuideScreen(onBack: () -> Unit) {
    SettingsScaffold(title = localizedText("镜像站格式示例"), onBack = onBack) { padding ->
        val markdown = if (androidx.compose.ui.platform.LocalConfiguration.current.locales[0].language == "en") {
            mirrorFormatMarkdownEnglish
        } else {
            mirrorFormatMarkdown
        }
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 16.dp)
        ) {
            markdown.lines().filter(String::isNotBlank).forEach { MirrorMarkdownLine(it) }
        }
    }
}

@Composable
private fun MirrorMarkdownLine(line: String) {
    val trimmed = line.trim()
    val linkColor = MaterialTheme.colorScheme.primary
    val keywordColor = MaterialTheme.colorScheme.tertiary
    val codeColor = MaterialTheme.colorScheme.onSurfaceVariant
    val annotatedLine = mirrorInlineMarkdown(trimmed, linkColor, keywordColor, codeColor)
    when {
        trimmed == "---" -> HorizontalDivider(modifier = Modifier.padding(vertical = 10.dp))
        trimmed.startsWith("## ") -> Text(
            mirrorInlineMarkdown(trimmed.removePrefix("## "), linkColor, keywordColor, codeColor),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(top = 12.dp, bottom = 8.dp)
        )
        trimmed.startsWith("### ") -> Text(
            mirrorInlineMarkdown(trimmed.removePrefix("### "), linkColor, keywordColor, codeColor),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(top = 8.dp, bottom = 5.dp)
        )
        trimmed.matches(Regex("\\d+\\. .*")) -> Text(annotatedLine, style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 22.sp), modifier = Modifier.padding(start = 4.dp, bottom = 5.dp))
        trimmed.startsWith("* ") -> Text(
            mirrorInlineMarkdown("• " + trimmed.removePrefix("* "), linkColor, keywordColor, codeColor),
            style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 22.sp),
            modifier = Modifier.padding(start = 16.dp, bottom = 5.dp)
        )
        else -> Text(annotatedLine, style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 22.sp), modifier = Modifier.padding(bottom = 7.dp))
    }
}

private fun mirrorInlineMarkdown(
    source: String,
    linkColor: Color,
    keywordColor: Color,
    codeColor: Color
): AnnotatedString = buildAnnotatedString {
    val token = Regex("(\\*\\*.*?\\*\\*|`.*?`|适合：)")
    var cursor = 0
    token.findAll(source).forEach { match ->
        append(source.substring(cursor, match.range.first))
        val value = match.value
        if (value.startsWith("**")) {
            pushStyle(SpanStyle(color = keywordColor, fontWeight = FontWeight.Bold))
            append(value.removeSurrounding("**"))
        } else if (value == "适合：") {
            pushStyle(SpanStyle(color = keywordColor, fontWeight = FontWeight.SemiBold))
            append(value)
        } else {
            val code = value.removeSurrounding("`")
            pushStyle(SpanStyle(color = codeColor, fontFamily = FontFamily.Monospace))
            var codeCursor = 0
            mirrorCodeToken.findAll(code).forEach { codeMatch ->
                append(code.substring(codeCursor, codeMatch.range.first))
                pushStyle(SpanStyle(color = if (codeMatch.value.startsWith("http")) linkColor else keywordColor))
                append(codeMatch.value)
                pop()
                codeCursor = codeMatch.range.last + 1
            }
            append(code.substring(codeCursor))
        }
        pop()
        cursor = match.range.last + 1
    }
    append(source.substring(cursor))
}
