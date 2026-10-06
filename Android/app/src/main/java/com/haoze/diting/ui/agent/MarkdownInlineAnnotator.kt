package com.haoze.diting.ui.agent

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration

/**
 * Regex matching inline Markdown spans:
 * - Bold & Italic: ***text*** or ___text___
 * - Bold: **text** or __text__
 * - Italic: *text* or _text_
 * - Strikethrough: ~~text~~
 * - Inline code: `code`
 * - Links: [label](url)
 * - Domain intelligence keywords: 【安全】 / 【高危】 / 【中风险】 / 【建议加入黑名单】 etc.
 */
private val INLINE_TOKEN_REGEX = Regex(
    """(\*\*\*[\s\S]+?\*\*\*|___[\s\S]+?___|\*\*[\s\S]+?\*\*|__[\s\S]+?__|~~[\s\S]+?~~|`[^`\n]+`|\[([^\]]+)\]\(([^)]+)\)|(?<!\*)\*(?!\*)[\s\S]+?(?<!\*)\*(?!\*)|(?<!_)_(?!_)[\s\S]+?(?<!_)_(?!_)|【(?:高危|高风险可疑|中风险|存在一般隐患|低风险|安全|健康良好|建议正常放行|建议加入白名单|建议加入屏蔽规则|建议旁路直连)】)"""
)

/**
 * Converts a string with inline Markdown elements into a formatted [AnnotatedString].
 */
@Composable
internal fun buildMarkdownAnnotatedString(
    source: String,
    baseColor: Color = MaterialTheme.colorScheme.onSurface,
    primaryColor: Color = MaterialTheme.colorScheme.primary,
    codeBackgroundColor: Color = MaterialTheme.colorScheme.surfaceContainerHighest,
    errorColor: Color = MaterialTheme.colorScheme.error,
    tertiaryColor: Color = MaterialTheme.colorScheme.tertiary
): AnnotatedString {
    return remember(source, baseColor, primaryColor, codeBackgroundColor, errorColor, tertiaryColor) {
        formatMarkdownAnnotatedString(
            source = source,
            baseColor = baseColor,
            primaryColor = primaryColor,
            codeBackgroundColor = codeBackgroundColor,
            errorColor = errorColor,
            tertiaryColor = tertiaryColor
        )
    }
}

/**
 * Pure function formatting inline Markdown spans into [AnnotatedString].
 */
internal fun formatMarkdownAnnotatedString(
    source: String,
    baseColor: Color,
    primaryColor: Color,
    codeBackgroundColor: Color,
    errorColor: Color,
    tertiaryColor: Color
): AnnotatedString {
    return buildAnnotatedString {
        var cursor = 0
            INLINE_TOKEN_REGEX.findAll(source).forEach { match ->
                val start = match.range.first
                val end = match.range.last + 1
                if (start > cursor) {
                    append(source.substring(cursor, start))
                }

                val token = match.value
                when {
                    // Bold & Italic: ***text*** or ___text___
                    (token.startsWith("***") && token.endsWith("***") && token.length >= 6) ||
                            (token.startsWith("___") && token.endsWith("___") && token.length >= 6) -> {
                        val inner = token.substring(3, token.length - 3)
                        pushStyle(SpanStyle(fontWeight = FontWeight.Bold, fontStyle = FontStyle.Italic))
                        append(inner)
                        pop()
                    }

                    // Bold: **text** or __text__
                    (token.startsWith("**") && token.endsWith("**") && token.length >= 4) ||
                            (token.startsWith("__") && token.endsWith("__") && token.length >= 4) -> {
                        val inner = token.substring(2, token.length - 2)
                        val badgeColor = resolveBadgeColor(inner, primaryColor, errorColor, tertiaryColor)
                        pushStyle(SpanStyle(fontWeight = FontWeight.Bold, color = badgeColor ?: baseColor))
                        append(inner)
                        pop()
                    }

                    // Strikethrough: ~~text~~
                    token.startsWith("~~") && token.endsWith("~~") && token.length >= 4 -> {
                        val inner = token.substring(2, token.length - 2)
                        pushStyle(SpanStyle(textDecoration = TextDecoration.LineThrough))
                        append(inner)
                        pop()
                    }

                    // Inline code: `code`
                    token.startsWith("`") && token.endsWith("`") && token.length >= 2 -> {
                        val inner = token.substring(1, token.length - 1)
                        pushStyle(
                            SpanStyle(
                                fontFamily = FontFamily.Monospace,
                                background = codeBackgroundColor,
                                color = primaryColor,
                                fontWeight = FontWeight.Medium
                            )
                        )
                        append(" $inner ")
                        pop()
                    }

                    // Links: [label](url)
                    token.startsWith("[") && token.contains("](") && token.endsWith(")") -> {
                        val label = match.groupValues.getOrNull(2) ?: token
                        pushStyle(
                            SpanStyle(
                                color = primaryColor,
                                textDecoration = TextDecoration.Underline,
                                fontWeight = FontWeight.Medium
                            )
                        )
                        append(label)
                        pop()
                    }

                    // Italic: *text* or _text_
                    (token.startsWith("*") && token.endsWith("*") && token.length >= 2) ||
                            (token.startsWith("_") && token.endsWith("_") && token.length >= 2) -> {
                        val inner = token.substring(1, token.length - 1)
                        pushStyle(SpanStyle(fontStyle = FontStyle.Italic))
                        append(inner)
                        pop()
                    }

                    // Predefined AI Security & Decision Badges: 【安全】/【高危】...
                    token.startsWith("【") && token.endsWith("】") -> {
                        val badgeColor = resolveBadgeColor(token, primaryColor, errorColor, tertiaryColor) ?: primaryColor
                        pushStyle(SpanStyle(fontWeight = FontWeight.Bold, color = badgeColor))
                        append(token)
                        pop()
                    }

                    else -> {
                        append(token)
                    }
                }
                cursor = end
            }

            if (cursor < source.length) {
                append(source.substring(cursor))
            }
        }
    }

/**
 * Resolves highlighting colors for cybersecurity evaluation keywords in reports.
 */
private fun resolveBadgeColor(
    text: String,
    primaryColor: Color,
    errorColor: Color,
    tertiaryColor: Color
): Color? {
    return when {
        text.contains("高危") || text.contains("高风险") || text.contains("屏蔽规则") -> errorColor
        text.contains("中风险") || text.contains("存在一般隐患") -> Color(0xFFE65100) // Deep Orange
        text.contains("低风险") -> Color(0xFFF57F17) // Amber
        text.contains("安全") || text.contains("健康良好") || text.contains("白名单") -> Color(0xFF2E7D32) // Forest Green
        text.contains("正常放行") -> Color(0xFF1976D2) // Blue
        text.contains("旁路直连") -> tertiaryColor
        else -> null
    }
}
