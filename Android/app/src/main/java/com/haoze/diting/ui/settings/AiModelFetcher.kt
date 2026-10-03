package com.haoze.diting.ui.settings

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class AiApiException(message: String) : Exception(message)

/**
 * 向厂商拉取 OpenAI 兼容的 `GET {base}/models`，得到该 Key 真实可用的模型 ID 列表。
 * 模型候选完全来自在线拉取，避免硬编码型号过期。
 */
object AiModelFetcher {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    suspend fun fetchModelIds(baseUrl: String, apiKey: String): List<String> = withContext(Dispatchers.IO) {
        val endpoint = try {
            AgentApiClient.resolveModelsEndpoint(baseUrl)
        } catch (e: Exception) {
            throw AiApiException(e.message ?: "厂商基础地址不合法")
        }

        val request = Request.Builder()
            .url(endpoint)
            .apply {
                if (apiKey.isNotBlank()) {
                    header("Authorization", "Bearer ${apiKey.trim()}")
                }
                header("Accept", "application/json")
            }
            .get()
            .build()

        try {
            httpClient.newCall(request).execute().use { response ->
                val body = response.body?.string().orEmpty()
                if (!response.isSuccessful) {
                    throw AiApiException("HTTP ${response.code}: ${parseError(body).ifBlank { "服务端未返回错误详情" }}")
                }
                parseModelIds(body).ifEmpty {
                    throw AiApiException("接口未返回任何模型，请手动填写模型名称")
                }
            }
        } catch (e: AiApiException) {
            throw e
        } catch (e: Exception) {
            throw AiApiException("拉取模型列表失败：${e.message ?: e.javaClass.simpleName}")
        }
    }

    private fun parseModelIds(response: String): List<String> {
        val ids = mutableListOf<String>()
        val root = runCatching { JSONObject(response) }.getOrNull() ?: return emptyList()
        val array = root.optJSONArray("data")
            ?: root.optJSONArray("models")
            ?: root.optJSONArray("result")

        if (array != null) {
            for (i in 0 until array.length()) {
                val item = array.opt(i)
                val id = when {
                    item is JSONObject -> {
                        item.optString("id").ifBlank {
                            item.optString("model_id").ifBlank {
                                item.optString("name")
                            }
                        }
                    }
                    else -> item?.toString().orEmpty()
                }
                if (id.isNotBlank() && id !in ids) {
                    ids.add(id)
                }
            }
        }
        return ids.sorted()
    }

    private fun parseError(responseBody: String): String {
        return runCatching {
            val json = JSONObject(responseBody)
            val errorObj = json.optJSONObject("error")
            errorObj?.optString("message") ?: responseBody
        }.getOrDefault(responseBody)
    }
}
