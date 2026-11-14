package com.haoze.diting.automation

import android.content.ContentValues
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.haoze.diting.control.BlockPauseLink
import com.haoze.diting.log.LegacyDb
import com.haoze.diting.net.NetworkContextProbe
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/// 条件-动作自动化引擎（A1 / A13）：读取 `automation_rule`，按触发/条件求值，执行动作并记录
/// `automation_event`。
///
/// 判定与执行都在这一个对象里，UI 只写规则文档。触发时序来自平台（定时器 / 网络 / 手工），
/// 引擎不自己起线程：调用方在后台广播里同步调用 [evaluate]。同一规则有 60 秒冷却，避免一个事件
/// 重复触发。规则存储结构见 `automation_models.dart` 的 `AutomationSpec`。
object AutomationEngine {
    private const val TAG = "AutomationEngine"
    private const val DB_NAME = "diting_database"
    private const val COOLDOWN_MS = 60_000L

    private data class Rule(
        val id: String,
        val name: String,
        val priority: Int,
        val match: String,
        val spec: JSONObject,
    )

    /// 求值一个触发事件，返回本次真正执行的规则 id 列表。
    fun evaluate(context: Context, eventType: String): List<String> {
        val rules = loadRules(context)
        if (rules.isEmpty()) return emptyList()
        val now = System.currentTimeMillis()
        val prefs = prefs(context)
        val network = NetworkContextProbe.snapshot(context)
        val applied = ArrayList<String>()

        for (rule in rules.sortedByDescending { it.priority }) {
            val cooldownKey = "rule_last_run_${rule.id}"
            if (now - prefs.getLong(cooldownKey, 0L) < COOLDOWN_MS) continue
            if (!triggerMatches(rule.spec, eventType, now)) continue
            if (!conditionsMatch(rule.spec, rule.match, network)) continue
            val outcome = applyActions(prefs, rule.spec, now)
            prefs.edit().putLong(cooldownKey, now).apply()
            recordEvent(context, rule.id, eventType, outcome, now)
            applied.add(rule.id)
        }

        if (applied.isNotEmpty()) {
            runCatching { BlockPauseLink.apply(context) }
                .onFailure { Log.w(TAG, "应用暂停状态失败", it) }
            runCatching { StateBroadcaster.broadcast(context) }
                .onFailure { Log.w(TAG, "广播状态失败", it) }
        }
        return applied
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(AutomationContract.PREFS_NAME, Context.MODE_PRIVATE)

    private fun loadRules(context: Context): List<Rule> {
        val open = LegacyDb.open(context, DB_NAME)
        val db = (open as? LegacyDb.Open.Ready)?.db ?: return emptyList()
        val rules = ArrayList<Rule>()
        runCatching {
            db.query(
                "automation_rule",
                arrayOf("id", "name", "priority", "match", "spec_json"),
                "enabled = 1",
                null,
                null,
                null,
                "priority DESC",
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0) ?: continue
                    val raw = cursor.getString(4) ?: "{}"
                    val spec = runCatching { JSONObject(raw) }.getOrNull() ?: continue
                    rules.add(
                        Rule(
                            id = id,
                            name = cursor.getString(1) ?: "",
                            priority = cursor.getInt(2),
                            match = cursor.getString(3) ?: "all",
                            spec = spec,
                        )
                    )
                }
            }
        }.onFailure { Log.w(TAG, "读取自动化规则失败", it) }
        return rules
    }

    private fun triggerMatches(spec: JSONObject, eventType: String, now: Long): Boolean {
        val trigger = spec.optJSONObject("trigger") ?: return false
        if (trigger.optString("type") != eventType) return false
        if (eventType != AutomationSpecKeys.TRIGGER_SCHEDULE) return true
        val window = trigger.optJSONObject("window") ?: return true
        val calendar = Calendar.getInstance().apply { timeInMillis = now }
        val minuteOfDay = calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
        val start = window.optInt("startMin", 0)
        val end = window.optInt("endMin", 24 * 60)
        val inWindow = if (start <= end) {
            minuteOfDay in start until end
        } else {
            minuteOfDay >= start || minuteOfDay < end
        }
        if (!inWindow) return false
        val days = window.optJSONArray("days") ?: return true
        if (days.length() == 0) return true
        val isoDay = ((calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        for (index in 0 until days.length()) {
            if (days.optInt(index, -1) == isoDay) return true
        }
        return false
    }

    private fun conditionsMatch(
        spec: JSONObject,
        match: String,
        network: Map<String, Any?>,
    ): Boolean {
        val conditions = spec.optJSONArray("conditions") ?: return true
        if (conditions.length() == 0) return true
        val results = ArrayList<Boolean>()
        for (index in 0 until conditions.length()) {
            val condition = conditions.optJSONObject(index) ?: continue
            results.add(conditionMatches(condition, network))
        }
        if (results.isEmpty()) return true
        return if (match == "any") results.any { it } else results.all { it }
    }

    private fun conditionMatches(
        condition: JSONObject,
        network: Map<String, Any?>,
    ): Boolean {
        return when (condition.optString("type")) {
            "network" -> {
                val types = condition.optJSONArray("types") ?: return true
                if (types.length() == 0) return true
                val current = network["type"]
                (0 until types.length()).any { types.optString(it) == current }
            }
            // Unknown condition kinds never block a rule (forward compatible).
            else -> true
        }
    }

    private fun applyActions(
        prefs: SharedPreferences,
        spec: JSONObject,
        now: Long,
    ): String {
        val actions = spec.optJSONArray("actions") ?: return "none"
        val editor = prefs.edit()
        val applied = ArrayList<String>()
        for (index in 0 until actions.length()) {
            val action = actions.optJSONObject(index) ?: continue
            when (action.optString("type")) {
                AutomationSpecKeys.ACTION_PAUSE -> {
                    val minutes = action.optInt("minutes", 60).coerceAtLeast(1)
                    editor.putLong(
                        AutomationContract.KEY_PAUSED_UNTIL_MS,
                        now + minutes.toLong() * 60_000L,
                    )
                    applied.add("paused_${minutes}m")
                }
                AutomationSpecKeys.ACTION_SWITCH_PROFILE -> {
                    val id = action.optString("profileId")
                    if (id.isNotEmpty()) {
                        editor.putString(AutomationContract.KEY_ACTIVE_PROFILE, id)
                        applied.add("profile=$id")
                    }
                }
                AutomationSpecKeys.ACTION_SWITCH_UPSTREAM -> {
                    val tag = action.optString("upstreamTag")
                    if (tag.isNotEmpty()) {
                        editor.putString(AutomationContract.KEY_ACTIVE_UPSTREAM, tag)
                        applied.add("upstream=$tag")
                    }
                }
                AutomationSpecKeys.ACTION_TOGGLE_RULE_GROUP -> {
                    val group = action.optString("group")
                    if (group.isNotEmpty()) {
                        editor.putString(AutomationContract.KEY_ACTIVE_RULE_GROUP, group)
                        applied.add("group=$group")
                    }
                }
                AutomationSpecKeys.ACTION_BLOCK_SERVICES -> {
                    val services = action.optJSONArray("services") ?: JSONArray()
                    editor.putString(AutomationContract.KEY_BLOCKED_SERVICES, services.toString())
                    applied.add("services=${services.length()}")
                }
            }
        }
        editor.apply()
        return if (applied.isEmpty()) "none" else applied.joinToString(",")
    }

    private fun recordEvent(
        context: Context,
        ruleId: String,
        eventType: String,
        outcome: String,
        now: Long,
    ) {
        val open = LegacyDb.open(context, DB_NAME)
        val db = (open as? LegacyDb.Open.Ready)?.db ?: return
        runCatching {
            db.insert(
                "automation_event",
                null,
                ContentValues().apply {
                    put("ts", now)
                    put("rule_id", ruleId)
                    put("event", eventType)
                    put("outcome", outcome)
                },
            )
            db.update(
                "automation_rule",
                ContentValues().apply { put("last_run_at", now) },
                "id = ?",
                arrayOf(ruleId),
            )
        }.onFailure { Log.w(TAG, "写入自动化事件失败", it) }
    }
}

/// `AutomationSpec` 的字符串常量在 Dart 与 Kotlin 两侧必须一致。
private object AutomationSpecKeys {
    const val TRIGGER_SCHEDULE = "schedule"
    const val ACTION_PAUSE = "pause"
    const val ACTION_SWITCH_PROFILE = "switch_profile"
    const val ACTION_SWITCH_UPSTREAM = "switch_upstream"
    const val ACTION_TOGGLE_RULE_GROUP = "toggle_rule_group"
    const val ACTION_BLOCK_SERVICES = "block_services"
}
