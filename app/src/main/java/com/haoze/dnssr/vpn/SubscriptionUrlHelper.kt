package com.haoze.dnssr.vpn

import java.net.URI
import java.net.URLEncoder

internal object SubscriptionUrlHelper {
    val MIRROR_PLACEHOLDERS = setOf(
        "{url}", "{urlEncoded}", "{scheme}", "{host}", "{path}", "{pathAndQuery}"
    )

    fun normalizeMirrorTemplate(template: String?): String? {
        val normalized = template?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        require(MIRROR_PLACEHOLDERS.any { it in normalized }) {
            "镜像模板必须包含 {url}、{urlEncoded}、{scheme}、{host}、{path} 或 {pathAndQuery}"
        }
        buildMirrorUrl(normalized, "https://example.com/rules.txt")
        return normalized
    }

    fun buildMirrorUrl(template: String, originalUrl: String): String {
        val encoded = URLEncoder.encode(originalUrl, Charsets.UTF_8.name()).replace("+", "%20")
        val uri = runCatching { URI(originalUrl) }.getOrElse {
            throw IllegalArgumentException("原始订阅地址格式无效", it)
        }
        val path = uri.rawPath?.takeIf { it.isNotEmpty() } ?: "/"
        val pathAndQuery = path + (uri.rawQuery?.let { "?$it" } ?: "")
        val result = template
            .replace("{urlEncoded}", encoded)
            .replace("{url}", originalUrl)
            .replace("{scheme}", uri.scheme.orEmpty())
            .replace("{host}", uri.host.orEmpty())
            .replace("{pathAndQuery}", pathAndQuery)
            .replace("{path}", path)
        require(result.startsWith("https://") || result.startsWith("http://")) {
            "镜像模板生成的地址必须使用 HTTP 或 HTTPS"
        }
        return result
    }

    fun extractNameFromUrl(url: String): String {
        return try {
            val uri = URI(url)
            val path = uri.path ?: ""
            val fileName = path.substringAfterLast('/')
            if (fileName.isNotBlank()) fileName else uri.host ?: url
        } catch (_: Exception) {
            url
        }
    }

    fun countRules(content: String): Int = content.lineSequence().sumOf { line ->
        val parsed = AdGuardRuleParser.parseCategorizedLine(line)
        parsed.blockRules.size + parsed.allowRules.size + parsed.rewriteRules.size
    }
}
