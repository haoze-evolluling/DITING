package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.GoUrlRuleKind
import org.json.JSONArray
import org.json.JSONObject

enum class AddressRuleBackupSource(val storageValue: String) {
    SUBSCRIPTIONS("subscriptions"),
    MANUAL("manual"),
    ALL("all")
}

data class AddressRuleBackup(
    val source: AddressRuleBackupSource,
    val blockRules: List<String>,
    val allowRules: List<String>
) {
    val totalCount: Int get() = blockRules.size + allowRules.size
}

object AddressRuleBackupCodec {
    private const val FORMAT = "dnssr_address_rule_backup"
    private const val VERSION = 1

    fun encode(backup: AddressRuleBackup): String = JSONObject()
        .put("format", FORMAT)
        .put("version", VERSION)
        .put("source", backup.source.storageValue)
        .put("rules", JSONObject()
            .put("block", JSONArray(backup.blockRules))
            .put("allow", JSONArray(backup.allowRules)))
        .toString(2)

    fun decode(content: String): AddressRuleBackup {
        val root = runCatching { JSONObject(content) }
            .getOrElse { throw IllegalArgumentException("地址规则备份不是有效的 JSON") }
        require(root.optString("format") == FORMAT) { "不是地址规则备份文件" }
        require(root.optInt("version", -1) == VERSION) { "不支持的地址规则备份版本" }
        val source = AddressRuleBackupSource.entries.firstOrNull { it.storageValue == root.optString("source") }
            ?: throw IllegalArgumentException("备份包含不支持的规则来源")
        val rules = root.optJSONObject("rules") ?: throw IllegalArgumentException("备份缺少规则内容")
        return AddressRuleBackup(source, readRules(rules, "block", false), readRules(rules, "allow", true))
    }

    private fun readRules(rules: JSONObject, key: String, allow: Boolean): List<String> = buildList {
        val values = rules.optJSONArray(key) ?: throw IllegalArgumentException("备份缺少 $key 规则")
        for (index in 0 until values.length()) {
            val value = values.optString(index, "").trim()
            if (value.isEmpty()) throw IllegalArgumentException("备份规则格式错误")
            val normalized = if (allow && !value.startsWith("@@")) "@@$value" else value
            add(normalized)
        }
    }
}

object AddressRuleBackupTransfer {
    suspend fun export(database: AppDatabase, source: AddressRuleBackupSource): AddressRuleBackup {
        val rules = when (source) {
            AddressRuleBackupSource.SUBSCRIPTIONS -> emptyList()
            AddressRuleBackupSource.MANUAL,
            AddressRuleBackupSource.ALL -> database.goUrlRuleDao().enabledRulesBySource(GoUrlRuleManager.USER_SOURCE)
        }
        return AddressRuleBackup(
            source,
            rules.filter { it.kind == GoUrlRuleKind.BLOCK }.map { it.pattern }.sorted(),
            rules.filter { it.kind == GoUrlRuleKind.ALLOW }.map { it.pattern }.sorted()
        )
    }

    suspend fun restore(backup: AddressRuleBackup, manager: GoUrlRuleManager): Pair<Int, Int> {
        val block = backup.blockRules.count { manager.addRule(it) }
        val allow = backup.allowRules.count { manager.addRule(it) }
        return block to allow
    }
}
