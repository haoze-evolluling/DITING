package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.GoUrlRuleDao
import com.haoze.dnssr.data.entity.GoUrlRuleEntity
import com.haoze.dnssr.data.entity.GoUrlRuleKind
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

data class GoUrlRule(val pattern: String, val kind: String, val rawLine: String)

/** Parses and stores the intentionally small URL-prefix rule language used by Go tunnel filtering. */
class GoUrlRuleManager(private val dao: GoUrlRuleDao) {
    suspend fun addRule(line: String, source: String = USER_SOURCE): Boolean {
        val rule = parse(line) ?: return false
        return dao.insertForSource(
            GoUrlRuleEntity(pattern = rule.pattern, kind = rule.kind, rawLine = rule.rawLine, addedAt = System.currentTimeMillis()),
            source,
            true
        )
    }

    suspend fun enabledRules(): List<GoUrlRuleEntity> = dao.enabledRules()
    suspend fun count(kind: String): Int = dao.count(kind)
    suspend fun clearAll() = dao.clearAll()
    suspend fun delete(id: Long) = dao.deleteById(id)
    suspend fun setEnabled(id: Long, enabled: Boolean) = dao.setEnabled(id, enabled)

    suspend fun jsonSnapshot(): String = JSONArray().apply {
        dao.enabledRules().forEach { rule ->
            put(JSONObject().put("pattern", rule.pattern).put("kind", rule.kind))
        }
    }.toString()

    fun parse(line: String): GoUrlRule? {
        val raw = line.trim()
        val allow = raw.startsWith("@@")
        val value = raw.removePrefix("@@").trim()
        if (value.isEmpty() || value.contains('*') || value.contains('$')) return null
        val uri = runCatching { URI(value) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        if (uri.host.isNullOrBlank() || uri.userInfo != null || uri.fragment != null) return null
        val host = uri.host.lowercase()
        val port = uri.port.let { if (it == -1 || (scheme == "http" && it == 80) || (scheme == "https" && it == 443)) "" else ":$it" }
        val path = (uri.rawPath ?: "/").ifBlank { "/" }
        return GoUrlRule("$scheme://$host$port$path", if (allow) GoUrlRuleKind.ALLOW else GoUrlRuleKind.BLOCK, raw)
    }

    companion object { const val USER_SOURCE = "useradd" }
}
