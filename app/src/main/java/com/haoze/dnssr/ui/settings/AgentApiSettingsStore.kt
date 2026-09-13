package com.haoze.dnssr.ui.settings

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Global configuration data object for the host AI agent API.
 * Compatible with LLM providers that follow the /chat/completions spec, such as standard OpenAI, DeepSeek, and Moonshot AI.
 */
data class AgentApiConfig(
    val enabled: Boolean = true,
    val apiKey: String = "",
    val baseUrl: String = DEFAULT_BASE_URL,
    val model: String = DEFAULT_MODEL,
    val temperature: Double = DEFAULT_TEMPERATURE,
    val systemPrompt: String = ""
) {
    companion object {
        const val DEFAULT_BASE_URL = "https://api.deepseek.com/v1"

        /**
         * Factory-default model.
         *
         * Note: the former `deepseek-chat` / `deepseek-reasoner` model aliases were officially retired by
         * DeepSeek on 2026-07-24 and now return errors; the active models are the V4 series.
         */
        const val DEFAULT_MODEL = "deepseek-v4-flash"
        const val DEFAULT_TEMPERATURE = 0.7
    }
}

/**
 * Preset template for an agent API provider.
 *
 * Factory presets are provided by [AgentApiPresetStore.BUILTIN_PRESETS]; user-defined entries are persisted in
 * local private storage. Merging the two yields the full preset list offered on the settings page.
 */
data class ModelPreset(
    val id: String,
    val name: String,
    val baseUrl: String,
    val model: String,
    val description: String = "",
    val builtin: Boolean = false
) {
    /** Whether this is a macOS / private-gateway style custom node (not an official preset). */
    val isCustom: Boolean get() = !builtin
}

/**
 * Repository for agent API provider preset templates.
 *
 * Core mechanics:
 * 1. Factory presets ship with the code: they are always available and cannot be deleted, while custom entries can be edited and deleted in the management panel;
 * 2. User-defined presets are persisted in SharedPreferences (a JSON array) and support add/edit/delete;
 * 3. Display order is persisted as a separate id sequence, so built-in and custom entries can be interleaved. The reordering
 *    entry point is currently not exposed in the UI; [movePreset] keeps the capability so it can be restored later.
 */
object AgentApiPresetStore {

    private const val KEY_CUSTOM_PRESETS = "agent_api_custom_presets"
    private const val KEY_PRESET_ORDER = "agent_api_preset_order"

    /**
     * Factory built-in presets. Model names are maintained against each vendor's retirement schedule and must stay in
     * sync with the vendors' currently active models. Last verified: 2026-09.
     */
    val BUILTIN_PRESETS: List<ModelPreset> = listOf(
        ModelPreset(
            id = "builtin_deepseek_v4_flash",
            name = "DeepSeek V4 Flash",
            baseUrl = "https://api.deepseek.com/v1",
            model = "deepseek-v4-flash",
            description = "经济首选，1M 上下文",
            builtin = true
        ),
        ModelPreset(
            id = "builtin_deepseek_v4_pro",
            name = "DeepSeek V4 Pro",
            baseUrl = "https://api.deepseek.com/v1",
            model = "deepseek-v4-pro",
            description = "旗舰推理，适合复杂研判",
            builtin = true
        ),
        ModelPreset(
            id = "builtin_openai_terra",
            name = "OpenAI GPT-5.6 Terra",
            baseUrl = "https://api.openai.com/v1",
            model = "gpt-5.6-terra",
            description = "均衡档，日常生产可用",
            builtin = true
        ),
        ModelPreset(
            id = "builtin_openai_luna",
            name = "OpenAI GPT-5.6 Luna",
            baseUrl = "https://api.openai.com/v1",
            model = "gpt-5.6-luna",
            description = "高并发低成本档",
            builtin = true
        ),
        ModelPreset(
            id = "builtin_moonshot_kimi",
            name = "Moonshot Kimi K3",
            baseUrl = "https://api.moonshot.cn/v1",
            model = "kimi-k3",
            description = "长上下文与工具调用",
            builtin = true
        )
    )

    /** Candidate suggestions when a model name is typed manually (covers only the active models of the providers used by the built-in presets). */
    val MODEL_SUGGESTIONS: List<String> = listOf(
        "deepseek-v4-flash",
        "deepseek-v4-pro",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
        "gpt-5.4-mini",
        "kimi-k3"
    )

    /**
     * Migration map from legacy model names to their active replacements.
     * Used on upgrade: when a user still has a retired model name persisted locally, it is silently corrected on read.
     */
    val LEGACY_MODEL_MIGRATIONS: Map<String, String> = mapOf(
        "deepseek-chat" to "deepseek-v4-flash",
        "deepseek-reasoner" to "deepseek-v4-pro",
        "deepseek-ai/DeepSeek-V3" to "deepseek-ai/DeepSeek-V4-Flash",
        "deepseek-ai/DeepSeek-V3.1" to "deepseek-ai/DeepSeek-V4-Flash",
        "deepseek-ai/DeepSeek-V3.2" to "deepseek-ai/DeepSeek-V4-Flash",
        "deepseek-ai/DeepSeek-R1" to "deepseek-ai/DeepSeek-V4-Pro",
        "moonshot-v1-8k" to "kimi-k3",
        "moonshot-v1-32k" to "kimi-k3",
        "moonshot-v1-128k" to "kimi-k3",
        "gpt-4o-mini" to "gpt-5.4-mini",
        "gpt-4o" to "gpt-5.6-terra",
        "qwen-plus" to "qwen3.6-27b",
        "qwen-max" to "qwen3.7-max"
    )

    /** Maps a legacy model name to the active model name; non-legacy values are returned unchanged. */
    fun migrateLegacyModelName(model: String): String {
        val trimmed = model.trim()
        if (trimmed.isEmpty()) return AgentApiConfig.DEFAULT_MODEL
        return LEGACY_MODEL_MIGRATIONS[trimmed] ?: trimmed
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Reads user-defined presets (in storage order). */
    fun getCustomPresets(context: Context): List<ModelPreset> {
        val raw = prefs(context).getString(KEY_CUSTOM_PRESETS, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.optJSONObject(i) ?: continue
                    val baseUrl = obj.optString("baseUrl").trim()
                    val model = obj.optString("model").trim()
                    val name = obj.optString("name").trim()
                    if (baseUrl.isEmpty() || model.isEmpty()) continue
                    add(
                        ModelPreset(
                            id = obj.optString("id").takeIf { it.isNotBlank() }
                                ?: "custom_${UUID.randomUUID().toString().take(8)}",
                            name = name.ifBlank { model },
                            baseUrl = baseUrl,
                            model = model,
                            description = obj.optString("description").trim(),
                            builtin = false
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    /** Reads the full preset list (built-in + custom), ordered by the user's adjusted ordering. */
    fun getOrderedPresets(context: Context): List<ModelPreset> {
        val all = BUILTIN_PRESETS + getCustomPresets(context)
        val savedOrder = prefs(context).getString(KEY_PRESET_ORDER, null)
            ?.split(',')
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            .orEmpty()
        if (savedOrder.isEmpty()) return all

        val byId = all.associateBy { it.id }
        val ordered = savedOrder.mapNotNull { byId[it] }
        val orderedIds = ordered.map { it.id }.toSet()
        // Newly added presets (not yet present in the order table) are appended to the end
        return ordered + all.filter { it.id !in orderedIds }
    }

    /** Adds or updates a custom preset and returns the updated full list. */
    fun upsertCustomPreset(context: Context, preset: ModelPreset): List<ModelPreset> {
        val target = preset.copy(
            id = preset.id.ifBlank { "custom_${UUID.randomUUID().toString().take(8)}" },
            name = preset.name.trim().ifBlank { preset.model.trim() },
            baseUrl = preset.baseUrl.trim().trimEnd('/'),
            model = preset.model.trim(),
            builtin = false
        )
        val current = getCustomPresets(context).toMutableList()
        val index = current.indexOfFirst { it.id == target.id }
        if (index >= 0) current[index] = target else current.add(target)
        saveCustomPresets(context, current)
        return getOrderedPresets(context)
    }

    /** Deletes a custom preset (built-in presets cannot be deleted) and returns the updated full list. */
    fun deleteCustomPreset(context: Context, presetId: String): List<ModelPreset> {
        val current = getCustomPresets(context).filterNot { it.id == presetId }
        saveCustomPresets(context, current)
        // Also removes stale ids from the order table
        val aliveIds = (BUILTIN_PRESETS + current).map { it.id }.toSet()
        saveOrder(context, getOrderedPresets(context).map { it.id }.filter { it in aliveIds })
        return getOrderedPresets(context)
    }

    /**
     * Adjusts the display order of a preset.
     * @param delta negative moves the preset up, positive moves it down.
     */
    fun movePreset(context: Context, presetId: String, delta: Int): List<ModelPreset> {
        val list = getOrderedPresets(context).toMutableList()
        val from = list.indexOfFirst { it.id == presetId }
        if (from < 0) return list
        val to = (from + delta).coerceIn(0, list.size - 1)
        if (to == from) return list
        list.add(to, list.removeAt(from))
        saveOrder(context, list.map { it.id })
        return list
    }

    /** Clears all custom presets and restores the default order. */
    fun resetToDefault(context: Context) {
        prefs(context).edit()
            .remove(KEY_CUSTOM_PRESETS)
            .remove(KEY_PRESET_ORDER)
            .apply()
    }

    private fun saveCustomPresets(context: Context, presets: List<ModelPreset>) {
        val array = JSONArray()
        presets.forEach { preset ->
            array.put(
                JSONObject().apply {
                    put("id", preset.id)
                    put("name", preset.name)
                    put("baseUrl", preset.baseUrl)
                    put("model", preset.model)
                    put("description", preset.description)
                }
            )
        }
        prefs(context).edit().putString(KEY_CUSTOM_PRESETS, array.toString()).apply()
    }

    private fun saveOrder(context: Context, ids: List<String>) {
        prefs(context).edit().putString(KEY_PRESET_ORDER, ids.joinToString(",")).apply()
    }
}

/**
 * Persistence manager for the agent API configuration.
 */
object AgentApiSettingsStore {
    const val KEY_AGENT_API_ENABLED = "agent_api_enabled"
    const val KEY_AGENT_API_KEY = "agent_api_key"
    const val KEY_AGENT_BASE_URL = "agent_api_base_url"
    const val KEY_AGENT_MODEL = "agent_api_model"
    const val KEY_AGENT_TEMPERATURE = "agent_api_temperature"
    const val KEY_AGENT_SYSTEM_PROMPT = "agent_api_system_prompt"

    fun getAgentApiConfig(context: Context): AgentApiConfig {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val storedModel = prefs.getString(KEY_AGENT_MODEL, null)
        return AgentApiConfig(
            enabled = prefs.getBoolean(KEY_AGENT_API_ENABLED, true),
            apiKey = prefs.getString(KEY_AGENT_API_KEY, "").orEmpty(),
            baseUrl = prefs.getString(KEY_AGENT_BASE_URL, AgentApiConfig.DEFAULT_BASE_URL)
                .takeIf { !it.isNullOrBlank() } ?: AgentApiConfig.DEFAULT_BASE_URL,
            // Legacy model names (e.g. the retired deepseek-chat) are auto-corrected to the active model on read
            model = AgentApiPresetStore.migrateLegacyModelName(
                storedModel ?: AgentApiConfig.DEFAULT_MODEL
            ),
            temperature = prefs.getString(KEY_AGENT_TEMPERATURE, null)?.toDoubleOrNull()
                ?: AgentApiConfig.DEFAULT_TEMPERATURE,
            systemPrompt = prefs.getString(KEY_AGENT_SYSTEM_PROMPT, "").orEmpty()
        )
    }

    fun setAgentApiConfig(context: Context, config: AgentApiConfig) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_AGENT_API_ENABLED, config.enabled)
            .putString(KEY_AGENT_API_KEY, config.apiKey.trim())
            .putString(KEY_AGENT_BASE_URL, config.baseUrl.trim())
            .putString(KEY_AGENT_MODEL, config.model.trim())
            .putString(KEY_AGENT_TEMPERATURE, config.temperature.toString())
            .putString(KEY_AGENT_SYSTEM_PROMPT, config.systemPrompt.trim())
            .apply()
    }
}
