package com.haoze.diting.ui

import com.haoze.diting.ui.settings.AgentApiConfig
import org.json.JSONObject

/**
 * Text and clipboard parsing utilities for Agent API configuration.
 */
internal object AgentApiTextParser {

    /**
     * Attempts to extract a baseUrl and apiKey from a composite input string
     * that bundles both an HTTP(S) URL and an API key.
     * Returns Pair(baseUrl, apiKey) if recognized, or null otherwise.
     */
    fun parseCompositeUrlAndKey(input: String): Pair<String, String>? {
        if (!input.contains("http://") && !input.contains("https://")) {
            return null
        }
        val urlRegex = Regex("""https?://[^\s,;"'\(\)]+""")
        val urlMatch = urlRegex.find(input) ?: return null
        val extractedUrl = urlMatch.value.trimEnd('/')
        val remaining = input.replace(urlMatch.value, "")
            .removePrefix("Bearer ")
            .replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "")
            .trim(',', ';', ':', ' ')
        return if (remaining.isNotBlank()) {
            Pair(extractedUrl, remaining)
        } else {
            null
        }
    }

    /**
     * Smart-parses API text from the clipboard or user input:
     * 1. Strips carriage returns (\r), line feeds (\n), tabs (\t), and leading/
     *    trailing whitespace, fixing single-line input fields / soft keyboards
     *    truncating multi-line pastes and losing the tail;
     * 2. Removes the common "Bearer " prefix;
     * 3. Smart-compat with JSON configs, composite strings containing both Base
     *    URL and key (e.g. url,key or multi-line text), or a standalone API key.
     */
    fun parseAndApplyApiText(
        rawText: String,
        currentConfig: AgentApiConfig,
        onUpdate: (AgentApiConfig) -> Unit
    ): String {
        val text = rawText.trim()
        if (text.isBlank()) return "剪贴板为空"

        // 1. Try parsing as JSON
        if (text.startsWith("{") && text.endsWith("}")) {
            val parsedJson = runCatching {
                val json = JSONObject(text)
                var newConfig = currentConfig
                var updatedCount = 0
                val key = json.optString("apiKey").ifBlank { json.optString("api_key") }.ifBlank { json.optString("key") }
                val url = json.optString("baseUrl").ifBlank { json.optString("base_url") }.ifBlank { json.optString("url") }
                val model = json.optString("model")

                if (key.isNotBlank()) {
                    newConfig = newConfig.copy(apiKey = sanitizeInput(key))
                    updatedCount++
                }
                if (url.isNotBlank()) {
                    newConfig = newConfig.copy(baseUrl = sanitizeInput(url))
                    updatedCount++
                }
                if (model.isNotBlank()) {
                    newConfig = newConfig.copy(model = sanitizeInput(model))
                    updatedCount++
                }
                if (updatedCount > 0) {
                    onUpdate(newConfig)
                    "已从 JSON 中识别并更新 API 配置"
                } else null
            }.getOrNull()
            if (parsedJson != null) return parsedJson
        }

        // 2. Match composite content containing both a Base URL and an API key (multi-line text, comma- or @-separated, etc.)
        val urlRegex = Regex("""https?://[^\s,;"'\(\)]+""")
        val keyRegex = Regex("""(?:sk-[a-zA-Z0-9_\-]{16,}|(?:Bearer\s+)?([a-zA-Z0-9_\-]{32,}))""")

        val foundUrl = urlRegex.find(text)?.value?.trimEnd('/')
        val textWithoutUrl = if (foundUrl != null) text.replace(foundUrl, "") else text
        val foundKeyMatch = keyRegex.find(textWithoutUrl)
        val foundKey = foundKeyMatch?.value?.removePrefix("Bearer ")?.trim()

        if (foundUrl != null && !foundKey.isNullOrBlank()) {
            val sanitizedKey = sanitizeInput(foundKey)
            val sanitizedUrl = sanitizeInput(foundUrl)
            onUpdate(currentConfig.copy(baseUrl = sanitizedUrl, apiKey = sanitizedKey))
            return "已自动识别并填入服务地址与 API Key"
        }

        // 3. Only a server address was matched
        if (foundUrl != null && text.lines().size <= 2 && !text.contains("sk-")) {
            val sanitizedUrl = sanitizeInput(foundUrl)
            onUpdate(currentConfig.copy(baseUrl = sanitizedUrl))
            return "已填入服务地址"
        }

        // 4. Default to treating it as an API key: strip all newlines, carriage returns, tabs, and inner spaces to assemble the full long key
        val cleanedKey = sanitizeInput(text.removePrefix("Bearer "))
        onUpdate(currentConfig.copy(apiKey = cleanedKey))
        return "已填入 API Key"
    }

    /**
     * Sanitizes input string by stripping whitespace, newlines, carriage returns, and tabs.
     */
    fun sanitizeInput(input: String): String {
        return input
            .replace("\r", "")
            .replace("\n", "")
            .replace("\t", "")
            .replace(" ", "")
            .trim()
    }
}
