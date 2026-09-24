package com.haoze.diting.ui

import com.haoze.diting.ui.settings.AiProvider
import com.haoze.diting.ui.settings.AiProviderPresets
import com.haoze.diting.ui.settings.decodeAiProviders
import com.haoze.diting.ui.settings.encodeAiProviders
import com.haoze.diting.util.KeyObfuscator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AiProviderTest {

    @Test
    fun keyObfuscator_encryptsAndDecryptsProperly() {
        val testKey = "sk-ant-api03-abcdefg123456-XYZ!@#$"
        val sealed = KeyObfuscator.seal(testKey)

        assertNotEquals(testKey, sealed)
        assertTrue(sealed.isNotBlank())

        val opened = KeyObfuscator.open(sealed)
        assertEquals(testKey, opened)
    }

    @Test
    fun keyObfuscator_handlesEmptyAndBlank() {
        assertEquals("", KeyObfuscator.seal(""))
        assertEquals("", KeyObfuscator.seal("   "))
        assertEquals("", KeyObfuscator.open(""))
        assertEquals("", KeyObfuscator.open("invalid_base64_???"))
    }

    @Test
    fun aiProviders_serializationAndDeserialization() {
        val providers = listOf(
            AiProvider(
                id = "p1",
                name = "DeepSeek",
                baseUrl = "https://api.deepseek.com",
                apiKey = KeyObfuscator.seal("sk-123"),
                modelName = "deepseek-chat",
                presetId = "deepseek"
            ),
            AiProvider(
                id = "p2",
                name = "OpenAI",
                baseUrl = "https://api.openai.com/v1",
                apiKey = KeyObfuscator.seal("sk-456"),
                modelName = "gpt-4o",
                presetId = "openai"
            )
        )

        val json = encodeAiProviders(providers)
        assertTrue(json.startsWith("["))
        assertTrue(json.contains("DeepSeek"))
        assertTrue(json.contains("OpenAI"))

        val decoded = decodeAiProviders(json)
        assertEquals(2, decoded.size)
        assertEquals("p1", decoded[0].id)
        assertEquals("DeepSeek", decoded[0].name)
        assertEquals("deepseek-chat", decoded[0].modelName)
        assertEquals("sk-123", KeyObfuscator.open(decoded[0].apiKey))

        assertEquals("p2", decoded[1].id)
        assertEquals("OpenAI", decoded[1].name)
        assertEquals("gpt-4o", decoded[1].modelName)
        assertEquals("sk-456", KeyObfuscator.open(decoded[1].apiKey))
    }

    @Test
    fun aiProviderPresets_containsValidEntries() {
        val presets = AiProviderPresets.all
        assertTrue(presets.isNotEmpty())

        val ids = presets.map { it.id }
        assertEquals(ids.size, ids.distinct().size)

        for (preset in presets) {
            assertTrue(preset.baseUrl.startsWith("http://") || preset.baseUrl.startsWith("https://"))
            assertTrue(preset.name.isNotBlank())
            assertTrue(preset.group.isNotBlank())
        }
    }
}
