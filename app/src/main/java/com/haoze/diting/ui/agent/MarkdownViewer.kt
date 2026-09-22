package com.haoze.diting.ui.agent

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.diting.ui.copyToClipboard
import com.haoze.diting.ui.localizedText

/**
 * Represents structured Markdown blocks parsed from LLM text responses.
 */
internal sealed interface MarkdownBlock {
    data class Heading(val level: Int, val text: String) : MarkdownBlock
    data class Paragraph(val text: String) : MarkdownBlock
    data class BulletItem(val indent: Int, val text: String) : MarkdownBlock
    data class NumberedItem(val number: String, val text: String) : MarkdownBlock
    data class CodeBlock(val language: String, val code: String) : MarkdownBlock
    data class Blockquote(val text: String) : MarkdownBlock
    data object Divider : MarkdownBlock
    data class Table(val headers: List<String>, val rows: List<List<String>>) : MarkdownBlock
}

/**
 * Splits raw Markdown text into a list of structured [MarkdownBlock] items.
 */
internal fun parseMarkdownBlocks(rawText: String): List<MarkdownBlock> {
    val lines = rawText.lines()
    val blocks = mutableListOf<MarkdownBlock>()
    var i = 0
    val n = lines.size

    while (i < n) {
        val line = lines[i]
        val trimmed = line.trim()

        // 1. Skip empty lines
        if (trimmed.isEmpty()) {
            i++
            continue
        }

        // 2. Fenced code block (``` or ~~~)
        if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) {
            val delimiter = if (trimmed.startsWith("```")) "```" else "~~~"
            val lang = trimmed.removePrefix(delimiter).trim()
            val codeLines = mutableListOf<String>()
            i++
            while (i < n && !lines[i].trim().startsWith(delimiter)) {
                codeLines.add(lines[i])
                i++
            }
            if (i < n) i++ // skip closing delimiter
            blocks.add(MarkdownBlock.CodeBlock(lang, codeLines.joinToString("\n")))
            continue
        }

        // 3. Horizontal Rule (---, ***, ___)
        if (trimmed.matches(Regex("""^(?:-{3,}|\*{3,}|_{3,})$"""))) {
            blocks.add(MarkdownBlock.Divider)
            i++
            continue
        }

        // 4. Headings (# to ######)
        val headingMatch = Regex("""^(#{1,6})\s+(.+)$""").matchEntire(trimmed)
        if (headingMatch != null) {
            val level = headingMatch.groupValues[1].length
            val headingText = headingMatch.groupValues[2].trim()
            blocks.add(MarkdownBlock.Heading(level, headingText))
            i++
            continue
        }

        // 5. Blockquotes (> ...)
        if (trimmed.startsWith(">")) {
            val quoteLines = mutableListOf<String>()
            while (i < n && lines[i].trim().startsWith(">")) {
                quoteLines.add(lines[i].trim().removePrefix(">").trim())
                i++
            }
            blocks.add(MarkdownBlock.Blockquote(quoteLines.joinToString("\n")))
            continue
        }

        // 6. Tables: check if current line contains '|' and next line is a separator like |---|---|
        if (trimmed.startsWith("|") && trimmed.endsWith("|") && i + 1 < n) {
            val nextTrimmed = lines[i + 1].trim()
            val isTableSeparator = nextTrimmed.startsWith("|") &&
                    nextTrimmed.split("|").filter { it.isNotBlank() }.all { cell ->
                        cell.trim().matches(Regex("""^:?-+:?$"""))
                    }
            if (isTableSeparator) {
                val headerCells = trimmed.split("|")
                    .map { it.trim() }
                    .filterIndexed { idx, _ -> idx > 0 && idx < trimmed.split("|").lastIndex }
                i += 2 // skip header and separator line
                val rows = mutableListOf<List<String>>()
                while (i < n && lines[i].trim().startsWith("|") && lines[i].trim().endsWith("|")) {
                    val rowCells = lines[i].trim().split("|")
                        .map { it.trim() }
                        .filterIndexed { idx, _ -> idx > 0 && idx < lines[i].trim().split("|").lastIndex }
                    rows.add(rowCells)
                    i++
                }
                blocks.add(MarkdownBlock.Table(headerCells, rows))
                continue
            }
        }

        // 7. Unordered list item: - item, * item, + item (with optional leading indentation)
        val bulletMatch = Regex("""^(\s*)([-*+])\s+(.+)$""").find(line)
        if (bulletMatch != null) {
            val indentSpaces = bulletMatch.groupValues[1].length
            val indent = (indentSpaces / 2).coerceIn(0, 4)
            val content = bulletMatch.groupValues[3].trim()
            blocks.add(MarkdownBlock.BulletItem(indent, content))
            i++
            continue
        }

        // 8. Ordered list item: 1. item, 2. item
        val numMatch = Regex("""^(\s*)(\d+)\.\s+(.+)$""").find(line)
        if (numMatch != null) {
            val num = numMatch.groupValues[2]
            val content = numMatch.groupValues[3].trim()
            blocks.add(MarkdownBlock.NumberedItem("$num.", content))
            i++
            continue
        }

        // 9. Regular paragraph: collect consecutive non-empty lines
        val paragraphLines = mutableListOf<String>()
        while (i < n) {
            val curLine = lines[i]
            val curTrimmed = curLine.trim()
            if (curTrimmed.isEmpty()) break
            if (curTrimmed.startsWith("```") || curTrimmed.startsWith("~~~")) break
            if (curTrimmed.matches(Regex("""^(?:-{3,}|\*{3,}|_{3,})$"""))) break
            if (Regex("""^(#{1,6})\s+(.+)$""").matches(curTrimmed)) break
            if (curTrimmed.startsWith(">")) break
            if (Regex("""^(\s*)([-*+])\s+(.+)$""").matches(curLine)) break
            if (Regex("""^(\s*)(\d+)\.\s+(.+)$""").matches(curLine)) break
            if (curTrimmed.startsWith("|") && curTrimmed.endsWith("|")) break

            paragraphLines.add(curTrimmed)
            i++
        }
        if (paragraphLines.isNotEmpty()) {
            blocks.add(MarkdownBlock.Paragraph(paragraphLines.joinToString("\n")))
        }
    }
    return blocks
}

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
        buildAnnotatedString {
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

/**
 * Modern Material 3 Markdown viewer tailored for LLM analysis and cybersecurity reports.
 */
@Composable
fun MarkdownViewer(
    markdown: String,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val blocks = remember(markdown) { parseMarkdownBlocks(markdown) }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        blocks.forEach { block ->
            when (block) {
                is MarkdownBlock.Heading -> {
                    val topPadding = if (block.level <= 2) 10.dp else 4.dp
                    Spacer(modifier = Modifier.height(topPadding))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        if (block.level == 2) {
                            Box(
                                modifier = Modifier
                                    .size(width = 3.5.dp, height = 18.dp)
                                    .background(
                                        color = MaterialTheme.colorScheme.primary,
                                        shape = RoundedCornerShape(2.dp)
                                    )
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                        }
                        Text(
                            text = buildMarkdownAnnotatedString(block.text),
                            style = when (block.level) {
                                1 -> MaterialTheme.typography.titleLarge
                                2 -> MaterialTheme.typography.titleMedium
                                3 -> MaterialTheme.typography.titleSmall
                                else -> MaterialTheme.typography.bodyLarge
                            },
                            fontWeight = FontWeight.Bold,
                            color = if (block.level <= 3) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                        )
                    }
                }

                is MarkdownBlock.Paragraph -> {
                    Text(
                        text = buildMarkdownAnnotatedString(block.text),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        lineHeight = 22.sp
                    )
                }

                is MarkdownBlock.BulletItem -> {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = (block.indent * 14 + 4).dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        Surface(
                            shape = CircleShape,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .padding(top = 8.dp)
                                .size(5.dp)
                        ) {}
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = buildMarkdownAnnotatedString(block.text),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            lineHeight = 22.sp,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }

                is MarkdownBlock.NumberedItem -> {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 4.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        Text(
                            text = block.number,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = buildMarkdownAnnotatedString(block.text),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            lineHeight = 22.sp,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }

                is MarkdownBlock.CodeBlock -> {
                    Card(
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.85f)
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp)
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = block.language.ifBlank { "CODE" }.uppercase(),
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                IconButton(
                                    onClick = {
                                        context.copyToClipboard("code", block.code)
                                        Toast.makeText(context, localizedText(context, "代码已复制到剪贴板"), Toast.LENGTH_SHORT).show()
                                    },
                                    modifier = Modifier.size(24.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.ContentCopy,
                                        contentDescription = localizedText("复制代码"),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            }
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f),
                                modifier = Modifier.padding(vertical = 6.dp)
                            )
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState())
                            ) {
                                Text(
                                    text = block.code,
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 12.sp,
                                    lineHeight = 18.sp,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                            }
                        }
                    }
                }

                is MarkdownBlock.Blockquote -> {
                    Surface(
                        shape = RoundedCornerShape(topEnd = 10.dp, bottomEnd = 10.dp),
                        color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.45f),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(IntrinsicSize.Min)
                        ) {
                            Box(
                                modifier = Modifier
                                    .width(4.dp)
                                    .fillMaxHeight()
                                    .background(MaterialTheme.colorScheme.primary)
                            )
                            Spacer(modifier = Modifier.width(10.dp))
                            Text(
                                text = buildMarkdownAnnotatedString(block.text),
                                style = MaterialTheme.typography.bodyMedium,
                                fontStyle = FontStyle.Italic,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                lineHeight = 21.sp,
                                modifier = Modifier.padding(vertical = 8.dp, horizontal = 4.dp)
                            )
                        }
                    }
                }

                is MarkdownBlock.Divider -> {
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                        modifier = Modifier.padding(vertical = 4.dp)
                    )
                }

                is MarkdownBlock.Table -> {
                    Card(
                        shape = RoundedCornerShape(10.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.5f)
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp)
                    ) {
                        Box(modifier = Modifier.horizontalScroll(rememberScrollState())) {
                            Column(modifier = Modifier.padding(8.dp)) {
                                // Header row
                                Row(
                                    modifier = Modifier
                                        .background(
                                            color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f),
                                            shape = RoundedCornerShape(6.dp)
                                        )
                                        .padding(horizontal = 8.dp, vertical = 6.dp)
                                ) {
                                    block.headers.forEach { header ->
                                        Text(
                                            text = buildMarkdownAnnotatedString(header),
                                            style = MaterialTheme.typography.labelMedium,
                                            fontWeight = FontWeight.Bold,
                                            color = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier
                                                .widthIn(min = 90.dp)
                                                .padding(horizontal = 4.dp)
                                        )
                                    }
                                }

                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f),
                                    modifier = Modifier.padding(vertical = 4.dp)
                                )

                                // Data rows
                                block.rows.forEachIndexed { rowIndex, row ->
                                    Row(
                                        modifier = Modifier
                                            .background(
                                                color = if (rowIndex % 2 == 1) {
                                                    MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.3f)
                                                } else {
                                                    Color.Transparent
                                                },
                                                shape = RoundedCornerShape(4.dp)
                                            )
                                            .padding(horizontal = 8.dp, vertical = 6.dp)
                                    ) {
                                        row.forEach { cell ->
                                            Text(
                                                text = buildMarkdownAnnotatedString(cell),
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurface,
                                                modifier = Modifier
                                                    .widthIn(min = 90.dp)
                                                    .padding(horizontal = 4.dp)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
