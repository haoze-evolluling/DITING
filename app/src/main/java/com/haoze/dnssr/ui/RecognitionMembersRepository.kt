package com.haoze.dnssr.ui

import android.content.Context
import android.util.AtomicFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

data class RecognitionMembersConfiguration(
    val sponsors: List<RecognitionMember>,
    val coBuilders: List<RecognitionMember>
)

object RecognitionMembersRepository {
    private const val CONFIGURATION_URL =
        "https://raw.githubusercontent.com/haoze-evolluling/DITING/main/recognition_members.json"
    private const val CACHE_FILE_NAME = "recognition_members.json"
    private const val PREFERENCES_NAME = "recognition_members"
    private const val ETAG_KEY = "etag"
    private const val MAX_CONFIGURATION_BYTES = 256 * 1024L
    private val avatarFileNamePattern = Regex("[a-z0-9_]+_avatar\\.jpg")
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()
    private val refreshMutex = Mutex()

    suspend fun loadCached(context: Context): RecognitionMembersConfiguration =
        withContext(Dispatchers.IO) {
            readConfiguration(cacheFile(context)) ?: RecognitionMembersConfiguration(emptyList(), emptyList())
        }

    /** Returns a configuration only when the server provided a changed, valid document. */
    suspend fun refresh(context: Context): RecognitionMembersConfiguration? =
        withContext(Dispatchers.IO) {
            refreshMutex.withLock {
                val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                val request = Request.Builder().url(CONFIGURATION_URL).apply {
                    preferences.getString(ETAG_KEY, null)?.let { header("If-None-Match", it) }
                }.build()

                client.newCall(request).execute().use { response ->
                    if (response.code == 304) return@withLock null
                    if (!response.isSuccessful) throw IOException("HTTP ${response.code}")
                    val body = response.body ?: throw IOException("名单响应为空")
                    if (body.contentLength() > MAX_CONFIGURATION_BYTES) throw IOException("名单配置过大")
                    val json = body.byteStream().use { input ->
                        input.readBytesLimited(MAX_CONFIGURATION_BYTES).toString(Charsets.UTF_8)
                    }
                    val configuration = parseConfiguration(json)
                    writeCache(cacheFile(context), json)
                    preferences.edit().putString(ETAG_KEY, response.header("ETag")).apply()
                    configuration
                }
            }
        }

    private fun readConfiguration(file: File): RecognitionMembersConfiguration? =
        try {
            file.takeIf { it.isFile }?.readText()?.let(::parseConfiguration)
        } catch (_: Exception) {
            null
        }

    private fun parseConfiguration(json: String): RecognitionMembersConfiguration {
        val root = JSONObject(json)
        require(root.has("version") && !root.isNull("version")) { "名单配置缺少版本" }
        return RecognitionMembersConfiguration(
            sponsors = parseMembers(root.getJSONArray("sponsors"), "感谢您对谛听项目的赞助支持"),
            coBuilders = parseMembers(root.getJSONArray("coBuilders"), "感谢为谛听提出建议与帮助测试")
        ).also { configuration ->
            validateUniqueMembers(configuration.sponsors)
            validateUniqueMembers(configuration.coBuilders)
        }
    }

    private fun validateUniqueMembers(members: List<RecognitionMember>) {
        require(members.map(RecognitionMember::name).toSet().size == members.size) { "名单存在重复成员" }
        require(members.map(RecognitionMember::avatarFileName).toSet().size == members.size) { "名单存在重复头像" }
    }

    private fun parseMembers(members: JSONArray, acknowledgement: String): List<RecognitionMember> =
        List(members.length()) { index ->
            val member = members.getJSONObject(index)
            val name = member.getString("name").trim()
            val avatarFileName = member.getString("avatarFileName")
            require(name.isNotEmpty()) { "成员名称不能为空" }
            require(avatarFileName.matches(avatarFileNamePattern)) { "头像文件名无效" }
            RecognitionMember(name, avatarFileName, acknowledgement)
        }

    private fun cacheFile(context: Context): File = File(context.filesDir, CACHE_FILE_NAME)

    private fun writeCache(file: File, contents: String) {
        val atomicFile = AtomicFile(file)
        val output = atomicFile.startWrite()
        try {
            output.write(contents.toByteArray(Charsets.UTF_8))
            atomicFile.finishWrite(output)
        } catch (error: IOException) {
            atomicFile.failWrite(output)
            throw error
        }
    }

    private fun java.io.InputStream.readBytesLimited(maxBytes: Long): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var totalBytes = 0L
        while (true) {
            val count = read(buffer)
            if (count == -1) break
            totalBytes += count
            if (totalBytes > maxBytes) throw IOException("名单配置过大")
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }
}
