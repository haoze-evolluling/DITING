package com.haoze.diting.ui.settings

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

    data class ChatMessage(
        val role: String,
        val content: String
    )

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
                        put("content", "Hi, this is a connectivity test from DITING. Please reply with 'OK' and your model name in 10 words.")
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
     * Executes a chat completion request with the specified messages list.
     */
    suspend fun chat(
        config: AgentApiConfig,
        messages: List<ChatMessage>,
        temperatureOverride: Double? = null,
        timeoutSeconds: Long = 45L
    ): Result<AgentChatResult> = withContext(Dispatchers.IO) {
        runCatching {
            if (config.apiKey.isBlank()) {
                throw IllegalArgumentException("API Key 不能为空，请先在 AI 分析设置中配置")
            }

            val endpoint = resolveChatCompletionsEndpoint(config.baseUrl)
            val jsonMessages = JSONArray()
            messages.forEach { msg ->
                jsonMessages.put(JSONObject().apply {
                    put("role", msg.role)
                    put("content", msg.content)
                })
            }

            val requestJson = JSONObject().apply {
                put("model", config.model.ifBlank { AgentApiConfig.DEFAULT_MODEL })
                put("messages", jsonMessages)
                put("temperature", temperatureOverride ?: config.temperature)
            }

            val client = baseHttpClient.newBuilder()
                .readTimeout(timeoutSeconds, TimeUnit.SECONDS)
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
     * Performs structured intelligent cybersecurity & DNS analysis on a specific domain.
     */
    suspend fun analyzeDomain(
        config: AgentApiConfig,
        domain: String,
        recentContext: String? = null
    ): Result<AgentChatResult> {
        val systemPrompt = config.systemPrompt.ifBlank {
            "你是一名资深网络安全与 DNS 分析专家。你的任务是对用户给定的域名进行客观、准确、深入的安全分析。"
        }
        val userPrompt = buildString {
            appendLine("请对以下目标域名进行网络安全与解析特征分析：")
            appendLine("目标域名：$domain")
            if (!recentContext.isNullOrBlank()) {
                appendLine()
                appendLine("【近期设备请求与命中上下文】：")
                appendLine(recentContext.trim())
            }
            appendLine()
            appendLine("请按以下结构输出分析报告（使用 Markdown 标题与要点列表，保持清晰明确）：")
            appendLine("### 1. 域名归属与服务画像")
            appendLine("说明该域名所属厂商、业务分类（例如：核心云服务/CDN节点/常规业务/广告追踪/数据遥测/异常外联等）。")
            appendLine("### 2. 安全与风险评估")
            appendLine("明确给出风险评级：【安全】、【低风险】、【中风险】或【高危】，并说明原因（是否存在恶意挖矿、C2控制、钓鱼欺诈、隐私追踪等特征）。")
            appendLine("### 3. 处置建议")
            appendLine("给出具体处置建议：【建议正常放行】、【建议加入白名单】、【建议加入屏蔽规则】或【建议旁路直连】，并说明理由。")
            appendLine("### 4. 简要总结")
            appendLine("用 1~2 句话概括最终结论。")
        }

        val messages = listOf(
            ChatMessage(role = "system", content = systemPrompt),
            ChatMessage(role = "user", content = userPrompt)
        )
        return chat(config, messages)
    }

    /**
     * Performs holistic network security diagnosis on recent network traffic and DNS queries.
     */
    suspend fun analyzeNetworkTraffic(
        config: AgentApiConfig,
        trafficSummary: String
    ): Result<AgentChatResult> {
        val systemPrompt = config.systemPrompt.ifBlank {
            "你是一名网络安全与 DNS 流量分析专家，精通 DNS 协议、网络威胁防御和隐私保护。"
        }
        val userPrompt = buildString {
            appendLine("以下是当前设备近期产生的网络请求与 DNS 解析监控统计数据：")
            appendLine("---")
            appendLine(trafficSummary.trim())
            appendLine("---")
            appendLine()
            appendLine("请根据以上流量数据，生成一份网络安全分析报告（使用 Markdown 格式）：")
            appendLine("### 1. 总体网络安全状况")
            appendLine("评估当前网络健康度等级（【健康良好】/【存在一般隐患】/【高风险可疑】），总结当前网络请求的总体特征。")
            appendLine("### 2. 关键与异常请求分析")
            appendLine("指出数据中高频请求、被频繁拦截、具有潜在数据遥测或可疑外联行为的域名与协议。")
            appendLine("### 3. 防护效果评估")
            appendLine("分析当前软件规则拦截率是否处于合理区间，是否存在策略过度或防护盲区。")
            appendLine("### 4. 优化建议")
            appendLine("列举建议加入黑名单屏蔽的风险域名，以及可能误拦截建议加入白名单的业务域名。")
        }

        val messages = listOf(
            ChatMessage(role = "system", content = systemPrompt),
            ChatMessage(role = "user", content = userPrompt)
        )
        return chat(config, messages)
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
