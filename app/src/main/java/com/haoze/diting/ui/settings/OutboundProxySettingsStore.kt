package com.haoze.diting.ui.settings

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.haoze.diting.ui.OutboundProxyConfig
import com.haoze.diting.ui.OutboundProxyProtocol
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

import com.haoze.diting.ui.localizedText

object OutboundProxySettingsStore {
    private const val KEY_OUTBOUND_PROXY_ENABLED = "outbound_proxy_enabled"
    private const val KEY_OUTBOUND_PROXY_PROTOCOL = "outbound_proxy_protocol"
    private const val KEY_OUTBOUND_PROXY_HOST = "outbound_proxy_host"
    private const val KEY_OUTBOUND_PROXY_PORT = "outbound_proxy_port"
    private const val KEY_OUTBOUND_PROXY_USERNAME = "outbound_proxy_username"
    private const val KEY_OUTBOUND_PROXY_PASSWORD = "outbound_proxy_password"
    private const val KEY_OUTBOUND_PROXY_APP = "outbound_proxy_app"
    private const val KEY_OUTBOUND_PROXY_STATUS = "outbound_proxy_status"
    private const val KEY_OUTBOUND_PROXY_STATUS_MESSAGE = "outbound_proxy_status_message"

    @Volatile
    private var cachedConfig: OutboundProxyConfig? = null

    @Volatile
    private var currentStatus: Pair<String, String>? = null

    fun getOutboundProxyConfig(context: Context): OutboundProxyConfig {
        cachedConfig?.let { return it }
        return synchronized(this) {
            cachedConfig?.let { return@synchronized it }
            val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val config = OutboundProxyConfig(
                enabled = preferences.getBoolean(KEY_OUTBOUND_PROXY_ENABLED, false),
                protocol = OutboundProxyProtocol.fromStorageValue(preferences.getString(KEY_OUTBOUND_PROXY_PROTOCOL, null)),
                host = preferences.getString(KEY_OUTBOUND_PROXY_HOST, "127.0.0.1") ?: "127.0.0.1",
                port = preferences.getInt(KEY_OUTBOUND_PROXY_PORT, 7890),
                username = decryptProxySecret(preferences.getString(KEY_OUTBOUND_PROXY_USERNAME, null)),
                password = decryptProxySecret(preferences.getString(KEY_OUTBOUND_PROXY_PASSWORD, null)),
                proxyAppPackage = preferences.getString(KEY_OUTBOUND_PROXY_APP, "").orEmpty()
            )
            cachedConfig = config
            config
        }
    }

    fun setOutboundProxyConfig(context: Context, config: OutboundProxyConfig) {
        synchronized(this) {
            cachedConfig = config
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_OUTBOUND_PROXY_ENABLED, config.enabled)
                .putString(KEY_OUTBOUND_PROXY_PROTOCOL, config.protocol.storageValue)
                .putString(KEY_OUTBOUND_PROXY_HOST, config.host)
                .putInt(KEY_OUTBOUND_PROXY_PORT, config.port)
                .putString(KEY_OUTBOUND_PROXY_USERNAME, encryptProxySecret(config.username))
                .putString(KEY_OUTBOUND_PROXY_PASSWORD, encryptProxySecret(config.password))
                .putString(KEY_OUTBOUND_PROXY_APP, config.proxyAppPackage)
                .apply()
        }
    }

    fun isOutboundProxyEnabled(context: Context): Boolean {
        cachedConfig?.let { return it.enabled }
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return preferences.getBoolean(KEY_OUTBOUND_PROXY_ENABLED, false)
    }

    fun setOutboundProxyEnabled(context: Context, enabled: Boolean) {
        synchronized(this) {
            cachedConfig = cachedConfig?.copy(enabled = enabled)
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_OUTBOUND_PROXY_ENABLED, enabled)
                .apply()
        }
    }

    fun getOutboundProxyAppPackage(context: Context): String {
        cachedConfig?.let { return it.proxyAppPackage }
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return preferences.getString(KEY_OUTBOUND_PROXY_APP, "").orEmpty()
    }

    fun setOutboundProxyStatus(context: Context, state: String, message: String): Boolean {
        synchronized(this) {
            val current = currentStatus ?: getOutboundProxyStatus(context)
            if (current.first == state && current.second == message) {
                return false
            }
            currentStatus = state to message
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putString(KEY_OUTBOUND_PROXY_STATUS, state)
                .putString(KEY_OUTBOUND_PROXY_STATUS_MESSAGE, message)
                .apply()
            return true
        }
    }

    fun getOutboundProxyStatus(context: Context): Pair<String, String> {
        currentStatus?.let { return it }
        return synchronized(this) {
            currentStatus?.let { return@synchronized it }
            val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val status = preferences.getString(KEY_OUTBOUND_PROXY_STATUS, "disabled").orEmpty() to
                preferences.getString(KEY_OUTBOUND_PROXY_STATUS_MESSAGE, "").orEmpty()
            currentStatus = status
            status
        }
    }

    fun formatProxyErrorMessage(context: Context, rawError: String): String {
        if (rawError.isBlank()) return localizedText(context, "连接失败")
        val trimmed = rawError.trim()
        if (trimmed.startsWith("代理") || trimmed.startsWith("请选择") || trimmed.startsWith("不能选择") || trimmed.startsWith("所选")) {
            return localizedText(context, trimmed)
        }
        val lower = trimmed.lowercase()
        val localizedReason = when {
            lower.contains("connection refused") -> "代理未启动或端口未开放"
            lower.contains("timeout") || lower.contains("deadline exceeded") -> "连接代理超时"
            lower.contains("authentication failed") || lower.contains("407") -> "代理认证失败"
            lower.contains("rejected authentication") -> "代理不支持当前的认证方式"
            lower.contains("udp associate") -> "SOCKS5 代理不支持 UDP 转发"
            lower.contains("connect outbound proxy") -> "无法连接到代理服务"
            lower.contains("http proxy returned") -> "HTTP 代理返回错误"
            else -> trimmed
        }
        return localizedText(context, localizedReason)
    }

    private fun proxySecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey("diting_outbound_proxy", null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                "diting_outbound_proxy",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    private fun encryptProxySecret(value: String): String {
        if (value.isEmpty()) return ""
        return runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, proxySecretKey())
            val payload = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            Base64.encodeToString(payload, Base64.NO_WRAP)
        }.getOrDefault("")
    }

    private fun decryptProxySecret(value: String?): String {
        if (value.isNullOrEmpty()) return ""
        return runCatching {
            val payload = Base64.decode(value, Base64.NO_WRAP)
            val iv = payload.copyOfRange(0, 12)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, proxySecretKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(payload.copyOfRange(12, payload.size)), Charsets.UTF_8)
        }.getOrDefault("")
    }
}
