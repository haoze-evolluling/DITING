package com.haoze.diting.ui.settings

import org.json.JSONArray
import org.json.JSONObject

/**
 * 一条已配置的 AI 服务厂商。[presetId] 非空表示它由 [AiProviderPresets] 里的预设创建；
 * 手填地址的自定义厂商 presetId 为空。[modelName] 一律来自在线拉取或手填。
 * [apiKey] 在本地持久化时通过 [com.haoze.diting.util.KeyObfuscator] 进行混淆。
 */
data class AiProvider(
    val id: String,
    val name: String,
    val baseUrl: String,
    val apiKey: String = "",
    val modelName: String = "",
    val presetId: String = ""
)

/** 厂商列表与 SharedPreferences 里 providers_json 的编解码。 */
fun decodeAiProviders(raw: String): List<AiProvider> = try {
    val arr = JSONArray(raw)
    (0 until arr.length()).mapNotNull { i ->
        val obj = arr.optJSONObject(i) ?: return@mapNotNull null
        AiProvider(
            id = obj.optString("id"),
            name = obj.optString("name"),
            baseUrl = obj.optString("baseUrl"),
            apiKey = obj.optString("apiKey"),
            modelName = obj.optString("modelName"),
            presetId = obj.optString("presetId")
        )
    }
} catch (_: Exception) {
    emptyList()
}

fun encodeAiProviders(providers: List<AiProvider>): String {
    val arr = JSONArray()
    providers.forEach { p ->
        arr.put(JSONObject().apply {
            put("id", p.id)
            put("name", p.name)
            put("baseUrl", p.baseUrl)
            put("apiKey", p.apiKey)
            put("modelName", p.modelName)
            put("presetId", p.presetId)
        })
    }
    return arr.toString()
}

/**
 * 一个 OpenAI 兼容厂商的预设：只登记厂商名与接口地址，[baseUrl] 必须能直接拼出
 * `{baseUrl}/chat/completions`。
 * 可用模型一律由 [AiModelFetcher] 现场请求 `GET {baseUrl}/models` 取得。
 */
data class AiProviderPreset(
    val id: String,
    val name: String,
    val group: String,
    val baseUrl: String
)

/**
 * 内置 AI 厂商目录，供厂商管理页点选后预填接口地址。各 [AiProviderPreset.baseUrl] 均核对自厂商
 * 官方文档。
 */
object AiProviderPresets {

    const val GROUP_MAINLAND = "国内厂商"
    const val GROUP_OVERSEAS = "海外厂商"
    const val GROUP_AGGREGATOR = "聚合与本地部署"

    val all: List<AiProviderPreset> = listOf(
        AiProviderPreset("deepseek", "DeepSeek", GROUP_MAINLAND, "https://api.deepseek.com"),
        AiProviderPreset("zhipu", "智谱 GLM", GROUP_MAINLAND, "https://open.bigmodel.cn/api/paas/v4"),
        AiProviderPreset("moonshot", "Kimi（月之暗面）", GROUP_MAINLAND, "https://api.moonshot.cn/v1"),
        AiProviderPreset(
            "dashscope",
            "阿里云百炼（通义千问）",
            GROUP_MAINLAND,
            "https://dashscope.aliyuncs.com/compatible-mode/v1"
        ),
        AiProviderPreset("volcengine-ark", "火山方舟（豆包）", GROUP_MAINLAND, "https://ark.cn-beijing.volces.com/api/v3"),
        AiProviderPreset("minimax", "MiniMax", GROUP_MAINLAND, "https://api.minimax.io/v1"),
        AiProviderPreset("qianfan", "百度千帆（ERNIE）", GROUP_MAINLAND, "https://qianfan.baidubce.com/v2"),
        AiProviderPreset("stepfun", "阶跃星辰", GROUP_MAINLAND, "https://api.stepfun.com/v1"),
        AiProviderPreset("openai", "OpenAI", GROUP_OVERSEAS, "https://api.openai.com/v1"),
        AiProviderPreset(
            "gemini",
            "Google Gemini",
            GROUP_OVERSEAS,
            "https://generativelanguage.googleapis.com/v1beta/openai"
        ),
        AiProviderPreset("xai", "xAI Grok", GROUP_OVERSEAS, "https://api.x.ai/v1"),
        AiProviderPreset("mistral", "Mistral AI", GROUP_OVERSEAS, "https://api.mistral.ai/v1"),
        AiProviderPreset("groq", "Groq", GROUP_OVERSEAS, "https://api.groq.com/openai/v1"),
        AiProviderPreset("siliconflow", "硅基流动", GROUP_AGGREGATOR, "https://api.siliconflow.cn/v1"),
        AiProviderPreset("openrouter", "OpenRouter", GROUP_AGGREGATOR, "https://openrouter.ai/api/v1"),
        AiProviderPreset("ollama", "Ollama（本机）", GROUP_AGGREGATOR, "http://localhost:11434/v1")
    )
}
