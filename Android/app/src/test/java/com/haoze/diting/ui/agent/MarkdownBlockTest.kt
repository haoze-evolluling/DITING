package com.haoze.diting.ui.agent

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownBlockTest {

    @Test
    fun parseMarkdownBlocks_emptyAndWhitespace() {
        assertTrue(parseMarkdownBlocks("").isEmpty())
        assertTrue(parseMarkdownBlocks("   \n\n  \t  \n").isEmpty())
    }

    @Test
    fun parseMarkdownBlocks_headings() {
        val markdown = """
            # Heading 1
            ## Heading 2
            ### Heading 3
            ###### Heading 6
            #no-space
            ####### Heading 7
        """.trimIndent()
        val blocks = parseMarkdownBlocks(markdown)
        assertEquals(5, blocks.size)
        assertEquals(MarkdownBlock.Heading(1, "Heading 1"), blocks[0])
        assertEquals(MarkdownBlock.Heading(2, "Heading 2"), blocks[1])
        assertEquals(MarkdownBlock.Heading(3, "Heading 3"), blocks[2])
        assertEquals(MarkdownBlock.Heading(6, "Heading 6"), blocks[3])
        assertTrue(blocks[4] is MarkdownBlock.Paragraph)
    }

    @Test
    fun parseMarkdownBlocks_horizontalRule() {
        val markdown = """
            ---
            ***
            ___
            -----
        """.trimIndent()
        val blocks = parseMarkdownBlocks(markdown)
        assertEquals(4, blocks.size)
        assertTrue(blocks.all { it is MarkdownBlock.Divider })
    }

    @Test
    fun parseMarkdownBlocks_codeBlocks() {
        val markdown = """
            ```kotlin
            val a = 1
            val b = 2
            ```
            ~~~bash
            echo hello
            ~~~
        """.trimIndent()
        val blocks = parseMarkdownBlocks(markdown)
        assertEquals(2, blocks.size)

        val code1 = blocks[0] as MarkdownBlock.CodeBlock
        assertEquals("kotlin", code1.language)
        assertEquals("val a = 1\nval b = 2", code1.code)

        val code2 = blocks[1] as MarkdownBlock.CodeBlock
        assertEquals("bash", code2.language)
        assertEquals("echo hello", code2.code)
    }

    @Test
    fun parseMarkdownBlocks_unclosedCodeBlock() {
        val markdown = """
            ```java
            System.out.println("hello");
        """.trimIndent()
        val blocks = parseMarkdownBlocks(markdown)
        assertEquals(1, blocks.size)
        val code = blocks[0] as MarkdownBlock.CodeBlock
        assertEquals("java", code.language)
        assertEquals("System.out.println(\"hello\");", code.code)
    }

    @Test
    fun parseMarkdownBlocks_blockquotes() {
        val markdown = """
            > line 1
            > line 2
            > line 3
        """.trimIndent()
        val blocks = parseMarkdownBlocks(markdown)
        assertEquals(1, blocks.size)
        val quote = blocks[0] as MarkdownBlock.Blockquote
        assertEquals("line 1\nline 2\nline 3", quote.text)
    }

    @Test
    fun parseMarkdownBlocks_table() {
        val markdown = """
            | Header 1 | Header 2 | Header 3 |
            | :--- | :---: | ---: |
            | val1 | val2 | val3 |
            | val4 | val5 | val6 |
        """.trimIndent()
        val blocks = parseMarkdownBlocks(markdown)
        assertEquals(1, blocks.size)
        val table = blocks[0] as MarkdownBlock.Table
        assertEquals(listOf("Header 1", "Header 2", "Header 3"), table.headers)
        assertEquals(2, table.rows.size)
        assertEquals(listOf("val1", "val2", "val3"), table.rows[0])
        assertEquals(listOf("val4", "val5", "val6"), table.rows[1])
    }

    @Test(timeout = 2000)
    fun parseMarkdownBlocks_handlesNonTablePipesWithoutInfiniteLoop() {
        val input = """
            | not a table |
            just normal text
        """.trimIndent()
        val blocks = parseMarkdownBlocks(input)
        assertEquals(1, blocks.size)
        assertTrue(blocks[0] is MarkdownBlock.Paragraph)
    }

    @Test(timeout = 2000)
    fun parseMarkdownBlocks_handlesSingleLinePipeWithoutInfiniteLoop() {
        val input = "| single line pipe |"
        val blocks = parseMarkdownBlocks(input)
        assertEquals(1, blocks.size)
        assertTrue(blocks[0] is MarkdownBlock.Paragraph)
    }

    @Test(timeout = 2000)
    fun parseMarkdownBlocks_handlesEmptyPipesWithoutInfiniteLoop() {
        val input = """
            ||
            ||
        """.trimIndent()
        val blocks = parseMarkdownBlocks(input)
        assertEquals(1, blocks.size)
        assertTrue(blocks[0] is MarkdownBlock.Paragraph)
    }

    @Test
    fun parseMarkdownBlocks_lists() {
        val markdown = """
            - Item A
              - Subitem A1
                - Subitem A2
            * Item B
            + Item C
            1. Step 1
            2. Step 2
            10. Step 10
        """.trimIndent()
        val blocks = parseMarkdownBlocks(markdown)
        assertEquals(8, blocks.size)

        assertEquals(MarkdownBlock.BulletItem(0, "Item A"), blocks[0])
        assertEquals(MarkdownBlock.BulletItem(1, "Subitem A1"), blocks[1])
        assertEquals(MarkdownBlock.BulletItem(2, "Subitem A2"), blocks[2])
        assertEquals(MarkdownBlock.BulletItem(0, "Item B"), blocks[3])
        assertEquals(MarkdownBlock.BulletItem(0, "Item C"), blocks[4])

        assertEquals(MarkdownBlock.NumberedItem("1.", "Step 1"), blocks[5])
        assertEquals(MarkdownBlock.NumberedItem("2.", "Step 2"), blocks[6])
        assertEquals(MarkdownBlock.NumberedItem("10.", "Step 10"), blocks[7])
    }

    @Test
    fun parseMarkdownBlocks_mixedContent() {
        val markdown = """
            # AI Security Report
            This is a summary paragraph.
            It spans multiple lines.

            ---

            - Threat Level: High
            - Target: malicious.com

            ```json
            {"threat": true}
            ```

            > Recommendation: Block immediately.
        """.trimIndent()
        val blocks = parseMarkdownBlocks(markdown)
        assertEquals(7, blocks.size)
        assertTrue(blocks[0] is MarkdownBlock.Heading)
        assertTrue(blocks[1] is MarkdownBlock.Paragraph)
        assertTrue(blocks[2] is MarkdownBlock.Divider)
        assertTrue(blocks[3] is MarkdownBlock.BulletItem)
        assertTrue(blocks[4] is MarkdownBlock.BulletItem)
        assertTrue(blocks[5] is MarkdownBlock.CodeBlock)
        assertTrue(blocks[6] is MarkdownBlock.Blockquote)
    }

    @Test
    fun formatMarkdownAnnotatedString_styles() {
        val baseColor = Color.Black
        val primaryColor = Color.Blue
        val codeBgColor = Color.LightGray
        val errorColor = Color.Red
        val tertiaryColor = Color.Cyan

        // Bold test
        val boldRes = formatMarkdownAnnotatedString(
            source = "Hello **world** test",
            baseColor = baseColor,
            primaryColor = primaryColor,
            codeBackgroundColor = codeBgColor,
            errorColor = errorColor,
            tertiaryColor = tertiaryColor
        )
        assertEquals("Hello world test", boldRes.text)
        assertTrue(boldRes.spanStyles.any { it.item.fontWeight == FontWeight.Bold })

        // Italic test
        val italicRes = formatMarkdownAnnotatedString(
            source = "Hello *world* test",
            baseColor = baseColor,
            primaryColor = primaryColor,
            codeBackgroundColor = codeBgColor,
            errorColor = errorColor,
            tertiaryColor = tertiaryColor
        )
        assertEquals("Hello world test", italicRes.text)
        assertTrue(italicRes.spanStyles.any { it.item.fontStyle == FontStyle.Italic })

        // Strike test
        val strikeRes = formatMarkdownAnnotatedString(
            source = "Hello ~~deleted~~ test",
            baseColor = baseColor,
            primaryColor = primaryColor,
            codeBackgroundColor = codeBgColor,
            errorColor = errorColor,
            tertiaryColor = tertiaryColor
        )
        assertEquals("Hello deleted test", strikeRes.text)
        assertTrue(strikeRes.spanStyles.any { it.item.textDecoration == TextDecoration.LineThrough })

        // Code test
        val codeRes = formatMarkdownAnnotatedString(
            source = "Execute `cat /etc/hosts` now",
            baseColor = baseColor,
            primaryColor = primaryColor,
            codeBackgroundColor = codeBgColor,
            errorColor = errorColor,
            tertiaryColor = tertiaryColor
        )
        assertEquals("Execute  cat /etc/hosts  now", codeRes.text)
        assertTrue(codeRes.spanStyles.any { it.item.background == codeBgColor })

        // Link test
        val linkRes = formatMarkdownAnnotatedString(
            source = "Visit [OpenAI](https://openai.com) site",
            baseColor = baseColor,
            primaryColor = primaryColor,
            codeBackgroundColor = codeBgColor,
            errorColor = errorColor,
            tertiaryColor = tertiaryColor
        )
        assertEquals("Visit OpenAI site", linkRes.text)
        assertTrue(linkRes.spanStyles.any { it.item.color == primaryColor })

        // Badges test
        val badgeRes = formatMarkdownAnnotatedString(
            source = "评级: 【高危】 请注意",
            baseColor = baseColor,
            primaryColor = primaryColor,
            codeBackgroundColor = codeBgColor,
            errorColor = errorColor,
            tertiaryColor = tertiaryColor
        )
        assertEquals("评级: 【高危】 请注意", badgeRes.text)
        assertTrue(badgeRes.spanStyles.any { it.item.color == errorColor })
    }
}
