package com.haoze.dnssr.ui.settings

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Agent API client compatible with the OpenAI / DeepSeek API standards.
 * Used by the settings page for model listing and connectivity testing.
 */
object AgentApiClient {

    data class AgentChatResult(
        val content: String,
        val model: String,
        val promptTokens: Int = 0,
        val completionTokens: Int = 0,
        val totalTokens: Int = 0,
        val rawResponse: String? = null
    )

    private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()

    private val baseHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()

    /**
     * Fetches the server-side model list (OpenAI-compatible `GET /models`),
     * so users can pick from the models the provider actually offers.
     */
    suspend fun fetchModels(
        config: AgentApiConfig,
        timeoutSeconds: Long = 20L
    ): Result<List<String>> = withContext(Dispatchers.IO) {
        runCatching {
            if (config.apiKey.isBlank()) {
                throw IllegalArgumentException("API Key 不能为空")
            }

            val endpoint = resolveModelsEndpoint(config.baseUrl)
            val client = baseHttpClient.newBuilder()
                .readTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .build()

            val request = Request.Builder()
                .url(endpoint)
                .header("Authorization", "Bearer ${config.apiKey.trim()}")
                .get()
                .build()

            client.newCall(request).execute().use { response ->
                val body = response.body?.string().orEmpty()
                if (!response.isSuccessful) {
                    throw IllegalStateException(parseOpenAiError(body, response.code))
                }

                val json = JSONObject(body)
                val data = json.optJSONArray("data")
                    ?: json.optJSONArray("models")
                    ?: throw IllegalStateException("服务端未返回模型列表（响应中缺少 data 字段）")

                buildList {
                    for (i in 0 until data.length()) {
                        val obj = data.optJSONObject(i) ?: continue
                        val id = obj.optString("id").takeIf { it.isNotBlank() }
                            ?: obj.optString("name").takeIf { it.isNotBlank() }
                            ?: continue
                        add(id)
                    }
                }.distinct().sorted()
            }
        }
    }

    /**
     * Tests whether the given agent API configuration can communicate successfully.
     */
    suspend fun testConnection(config: AgentApiConfig): Result<AgentChatResult> =
        withContext(Dispatchers.IO) {
            runCatching {
                if (config.apiKey.isBlank()) {
                    throw IllegalArgumentException("API Key 不能为空")
                }

                val endpoint = resolveChatCompletionsEndpoint(config.baseUrl)
                val requestJson = JSONObject().apply {
                    put("model", config.model.ifBlank { AgentApiConfig.DEFAULT_MODEL })
                    put("messages", JSONArray().put(JSONObject().apply {
                        put("role", "user")
                        put("content", "Hi, this is a connectivity test from DITING DNSSR. Please reply with 'OK' and your model name in 10 words.")
                    }))
                    put("temperature", 0.1)
                }

                val client = baseHttpClient.newBuilder()
                    .readTimeout(15, TimeUnit.SECONDS)
                    .build()

                val request = Request.Builder()
                    .url(endpoint)
                    .header("Authorization", "Bearer ${config.apiKey.trim()}")
                    .header("Content-Type", "application/json")
                    .post(requestJson.toString().toRequestBody(JSON_MEDIA_TYPE))
                    .build()

                client.newCall(request).execute().use { response ->
                    val body = response.body?.string().orEmpty()
                    if (!response.isSuccessful) {
                        throw IllegalStateException(parseOpenAiError(body, response.code))
                    }

                    val jsonResponse = JSONObject(body)
                    val choices = jsonResponse.optJSONArray("choices")
                    val firstChoice = choices?.optJSONObject(0)
                    val messageObj = firstChoice?.optJSONObject("message")
                    val content = messageObj?.optString("content").orEmpty()

                    val usage = jsonResponse.optJSONObject("usage")
                    AgentChatResult(
                        content = content,
                        model = jsonResponse.optString("model", config.model),
                        promptTokens = usage?.optInt("prompt_tokens", 0) ?: 0,
                        completionTokens = usage?.optInt("completion_tokens", 0) ?: 0,
                        totalTokens = usage?.optInt("total_tokens", 0) ?: 0,
                        rawResponse = body
                    )
                }
            }
        }

    /**
     * Infers the OpenAI-standard `/models` endpoint from a Base URL.
     */
    fun resolveModelsEndpoint(rawBaseUrl: String): String {
        val trimmed = rawBaseUrl.trim().trimEnd('/')
        return when {
            trimmed.endsWith("/chat/completions") ->
                trimmed.removeSuffix("/chat/completions") + "/models"
            trimmed.endsWith("/v1") -> "$trimmed/models"
            trimmed.endsWith("/api") -> "$trimmed/v1/models"
            trimmed.equals("https://api.openai.com", ignoreCase = true) -> "$trimmed/v1/models"
            trimmed.equals("https://api.deepseek.com", ignoreCase = true) -> "$trimmed/v1/models"
            else -> "$trimmed/models"
        }
    }

    /**
     * Smart-completes the OpenAI-standard /chat/completions endpoint from a
     * Base URL.
     */
    fun resolveChatCompletionsEndpoint(rawBaseUrl: String): String {
        val trimmed = rawBaseUrl.trim().trimEnd('/')
        return when {
            trimmed.endsWith("/chat/completions") -> trimmed
            trimmed.endsWith("/v1") -> "$trimmed/chat/completions"
            trimmed.endsWith("/api") -> "$trimmed/v1/chat/completions"
            trimmed.equals("https://api.openai.com", ignoreCase = true) -> "$trimmed/v1/chat/completions"
            trimmed.equals("https://api.deepseek.com", ignoreCase = true) -> "$trimmed/v1/chat/completions"
            else -> "$trimmed/chat/completions"
        }
    }

    private fun parseOpenAiError(responseBody: String, httpCode: Int): String {
        return runCatching {
            val json = JSONObject(responseBody)
            val errorObj = json.optJSONObject("error")
            val message = errorObj?.optString("message")
            if (!message.isNullOrBlank()) {
                "AI 请求失败 ($httpCode): $message"
            } else {
                "AI 请求失败 ($httpCode): $responseBody"
            }
        }.getOrElse {
            "AI 请求失败 (HTTP $httpCode): $responseBody"
        }
    }
}
