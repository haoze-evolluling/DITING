package com.haoze.diting.ui.agent

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

private val HR_REGEX = Regex("""^(?:-{3,}|\*{3,}|_{3,})$""")
private val HEADING_REGEX = Regex("""^(#{1,6})\s+(.+)$""")
private val BULLET_REGEX = Regex("""^(\s*)([-*+])\s+(.+)$""")
private val NUMBERED_REGEX = Regex("""^(\s*)(\d+)\.\s+(.+)$""")
private val TABLE_SEPARATOR_CELL_REGEX = Regex("""^:?-+:?$""")

private fun isTableStart(lines: List<String>, index: Int): Boolean {
    if (index + 1 >= lines.size) return false
    val current = lines[index].trim()
    val next = lines[index + 1].trim()
    if (!current.startsWith("|") || !current.endsWith("|")) return false
    if (!next.startsWith("|") || !next.endsWith("|")) return false
    val cells = next.split("|").filter { it.isNotBlank() }
    return cells.isNotEmpty() && cells.all { it.trim().matches(TABLE_SEPARATOR_CELL_REGEX) }
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
        if (trimmed.matches(HR_REGEX)) {
            blocks.add(MarkdownBlock.Divider)
            i++
            continue
        }

        // 4. Headings (# to ######)
        val headingMatch = HEADING_REGEX.matchEntire(trimmed)
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

        // 6. Tables: check if current line starts a valid table
        if (isTableStart(lines, i)) {
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

        // 7. Unordered list item: - item, * item, + item (with optional leading indentation)
        val bulletMatch = BULLET_REGEX.find(line)
        if (bulletMatch != null) {
            val indentSpaces = bulletMatch.groupValues[1].length
            val indent = (indentSpaces / 2).coerceIn(0, 4)
            val content = bulletMatch.groupValues[3].trim()
            blocks.add(MarkdownBlock.BulletItem(indent, content))
            i++
            continue
        }

        // 8. Ordered list item: 1. item, 2. item
        val numMatch = NUMBERED_REGEX.find(line)
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
            if (curTrimmed.matches(HR_REGEX)) break
            if (HEADING_REGEX.matches(curTrimmed)) break
            if (curTrimmed.startsWith(">")) break
            if (BULLET_REGEX.matches(curLine)) break
            if (NUMBERED_REGEX.matches(curLine)) break
            if (isTableStart(lines, i)) break

            paragraphLines.add(curTrimmed)
            i++
        }
        if (paragraphLines.isNotEmpty()) {
            blocks.add(MarkdownBlock.Paragraph(paragraphLines.joinToString("\n")))
        } else {
            // Defensive safeguard against unexpected non-advancing loops
            i++
        }
    }
    return blocks
}
